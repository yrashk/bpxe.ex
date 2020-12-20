defmodule BPXE.Engine.Event do
  use GenServer
  use BPXE.Engine.FlowNode
  use BPXE.Engine.Blueprint.Recordable
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate([id: nil, type: nil, options: %{}, blueprint: nil, process: nil, activated: nil],
    persist: ~w(activated)a
  )

  def start_link(id, type, options, blueprint, process) do
    start_link([{id, type, options, blueprint, process}])
  end

  def add_signal_event_definition(pid, options) do
    call(pid, {:add_signal_event_definition, options})
  end

  def init({id, type, options, blueprint, process}) do
    :syn.register({blueprint.pid, :event, type, id}, self())

    state = %__MODULE__{
      id: id,
      type: type,
      options: options,
      blueprint: blueprint,
      process: process
    }

    state = initialize(state)
    # Done initializing
    init_ack()
    enter_loop(state)
  end

  def handle_call({:add_signal_event_definition, options}, _from, state) do
    # Camunda Modeler creates signalEventDefinitions without `signalRef`, just `id`,
    # so if `signalRef` is not used, fall back to `id`.
    :syn.join({state.blueprint.pid, :signal, options["signalRef"] || options["id"]}, self())
    {:reply, {:ok, options}, state}
  end

  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{type: :startEvent} = state) do
    Process.log(state.process, %Log.EventActivated{
      pid: self(),
      id: state.id,
      token_id: token.token_id
    })

    {:send, token, state}
  end

  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{type: :endEvent} = state) do
    Process.log(state.process, %Log.EventActivated{
      pid: self(),
      id: state.id,
      token_id: token.token_id
    })

    {:dontsend, state}
  end

  # Hold the tokens until event is trigerred
  def handle_token({%BPXE.Token{} = token, _id}, %__MODULE__{activated: nil} = state) do
    Process.log(state.process, %Log.EventActivated{
      pid: self(),
      id: state.id,
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
    Process.log(state.process, %Log.EventActivated{
      pid: self(),
      id: state.id,
      token_id: token.token_id
    })

    {:dontsend, %{state | activated: token}}
  end

  # When event is triggered, send the token
  def handle_info(
        {BPXE.Signal, _id},
        %__MODULE__{type: :intermediateCatchEvent, activated: activated, incoming: [_]} = state
      )
      when not is_nil(activated) do
    Process.log(state.process, %Log.EventTrigerred{
      pid: self(),
      id: state.id,
      token_id: activated.token_id
    })

    generation = next_generation(activated)
    activated = %{activated | __generation__: generation}

    Process.log(state.process, %Log.FlowNodeForward{
      pid: self(),
      id: state.id,
      token_id: activated.token_id,
      to: state.outgoing
    })

    state =
      Enum.reduce(state.outgoing, state, fn sequence_flow, state ->
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
