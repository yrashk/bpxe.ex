defmodule BPXE.Engine.Event do
  use GenServer
  use BPXE.Engine.FlowNode
  use BPXE.Engine.PropertyContainer
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log
  # TODO: catch events can have outputs
  # use BPXE.Engine.DataOutputAssociation

  defstate type: nil, activated: nil
  @persist_state :activated

  def start_link(element, attrs, model, process) do
    start_link([{element, attrs, model, process}])
  end

  def init({element, attrs, model, process}) do
    type = get_type(element)
    BPXE.Registry.register({model.pid, :event, type, attrs["id"]})

    state =
      %__MODULE__{type: type}
      |> put_state(Base, %{
        attrs: attrs,
        model: model,
        process: process
      })

    state = initialize(state)
    # Done initializing
    init_ack()
    enter_loop(state)
  end

  def handle_call({:add_node, _ref, "signalEventDefinition", attrs}, _from, state) do
    base_state = get_state(state, BPXE.Engine.Base)
    # Camunda Modeler creates signalEventDefinitions without `signalRef`, just `id`,
    # so if `signalRef` is not used, fall back to `id`.
    BPXE.Channel.join({base_state.model.pid, :signal, attrs["signalRef"] || attrs["id"]})
    {:reply, {:ok, {self(), :signal_event_definition}}, state}
  end

  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{type: :startEvent} = state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventActivated{
      pid: self(),
      id: base_state.attrs["id"],
      token_id: token.token_id
    })

    {:send, token, state}
  end

  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{type: :endEvent} = state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventActivated{
      pid: self(),
      id: base_state.attrs["id"],
      token_id: token.token_id
    })

    {:dontsend, state}
  end

  # Hold the tokens until event is trigerred
  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{activated: nil} = state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventActivated{
      pid: self(),
      id: base_state.attrs["id"],
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
      id: base_state.attrs["id"],
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

    Process.log(base_state.process, %Log.EventTriggered{
      pid: self(),
      id: base_state.attrs["id"],
      token_id: activated.token_id
    })

    generation = next_generation(activated)
    activated = %{activated | __generation__: generation}

    flow_node_state = get_state(state, BPXE.Engine.FlowNode)

    Process.log(base_state.process, %Log.FlowNodeForward{
      pid: self(),
      id: base_state.attrs["id"],
      token_id: activated.token_id,
      to: flow_node_state.outgoing
    })

    process_sequence_flows = sequence_flows(state)
    outgoing = Enum.map(flow_node_state.outgoing, &process_sequence_flows[&1])

    state =
      Enum.reduce(outgoing, state, fn sequence_flow, state ->
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

  defp get_type(name), do: String.to_atom(name)

  import BPXE.Engine.BPMN

  def add_signal_event_definition(pid, attrs, body \\ nil) do
    add_node(pid, "signalEventDefinition", attrs, body)
  end
end
