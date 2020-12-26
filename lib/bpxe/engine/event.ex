defmodule BPXE.Engine.Event do
  use GenServer
  use BPXE.Engine.FlowNode
  use BPXE.Engine.Model.Recordable
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate type: nil, activated: nil
  @persist_state :activated

  def start_link(id, type, attrs, model, process) do
    start_link([{id, type, attrs, model, process}])
  end

  def add_signal_event_definition(pid, attrs) do
    call(pid, {:add_signal_event_definition, attrs})
  end

  def init({id, type, attrs, model, process}) do
    :syn.register({model.pid, :event, type, id}, self())

    state =
      %__MODULE__{type: type}
      |> put_state(Base, %{
        id: id,
        attrs: attrs,
        model: model,
        process: process
      })

    state = initialize(state)
    # Done initializing
    init_ack()
    enter_loop(state)
  end

  def handle_call({:add_signal_event_definition, attrs}, _from, state) do
    base_state = get_state(state, BPXE.Engine.Base)
    # Camunda Modeler creates signalEventDefinitions without `signalRef`, just `id`,
    # so if `signalRef` is not used, fall back to `id`.
    :syn.join({base_state.model.pid, :signal, attrs["signalRef"] || attrs["id"]}, self())
    {:reply, {:ok, attrs}, state}
  end

  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{type: :startEvent} = state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventActivated{
      pid: self(),
      id: base_state.id,
      token_id: token.token_id
    })

    {:send, token, state}
  end

  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{type: :endEvent} = state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventActivated{
      pid: self(),
      id: base_state.id,
      token_id: token.token_id
    })

    {:dontsend, state}
  end

  # Hold the tokens until event is trigerred
  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{activated: nil} = state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventActivated{
      pid: self(),
      id: base_state.id,
      token_id: token.token_id
    })

    {:dontsend, %{state | activated: token}}
  end

  # If a different token comes, forget the previous one we held,
  # overwrite it with the new one (FIXME: not sure this is a good default behaviour)
  def handle_token(
        {%BPXE.Token{token_id: token_id} = token, _id},
        %__MODULE__{activated: %BPXE.Token{token_id: token_id1}} = state
      )
      when token_id != token_id1 do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventActivated{
      pid: self(),
      id: base_state.id,
      token_id: token.token_id
    })

    {:dontsend, %{state | activated: token}}
  end

  # When event is triggered, send the token
  def handle_info(
        {BPXE.Signal, _id},
        %__MODULE__{
          type: :intermediateCatchEvent,
          activated: activated,
          __layers__: %{FlowNode => %{incoming: [_]}}
        } = state
      )
      when not is_nil(activated) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventTrigerred{
      pid: self(),
      id: base_state.id,
      token_id: activated.token_id
    })

    generation = next_generation(activated)
    activated = %{activated | __generation__: generation}

    flow_node_state = get_state(state, BPXE.Engine.FlowNode)

    Process.log(base_state.process, %Log.FlowNodeForward{
      pid: self(),
      id: base_state.id,
      token_id: activated.token_id,
      to: flow_node_state.outgoing
    })

    state =
      Enum.reduce(flow_node_state.outgoing, state, fn sequence_flow, state ->
        send_token(sequence_flow, activated, state)
      end)

    save_state(generation, state)

    {:noreply, handle_completion(state)}
  end

  def handle_info({BPXE.Signal, _id}, state) do
    {:noreply, state}
  end

  def handle_completion(%__MODULE__{type: :endEvent} = state) do
    super(state)
  end

  def handle_completion(state) do
    super(state)
  end
end
