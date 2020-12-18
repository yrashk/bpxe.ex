defmodule BPEXE.Engine.Event do
  use GenServer
  use BPEXE.Engine.FlowNode
  alias BPEXE.Engine.Process
  alias BPEXE.Engine.Process.Log

  defstate([id: nil, type: nil, options: %{}, instance: nil, process: nil, activated: nil],
    persist: ~w(activated)a
  )

  def start_link(id, type, options, instance, process) do
    start_link([{id, type, options, instance, process}])
  end

  def add_signal_event_definition(pid, options) do
    GenServer.call(pid, {:add_signal_event_definition, options})
  end

  def init({id, type, options, instance, process}) do
    :syn.register({instance.pid, :event, type, id}, self())

    state = %__MODULE__{
      id: id,
      type: type,
      options: options,
      instance: instance,
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
    :syn.join({state.instance.pid, :signal, options["signalRef"] || options["id"]}, self())
    {:reply, {:ok, options}, state}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{type: :startEvent} = state) do
    Process.log(state.process, %Log.EventActivated{pid: self(), id: state.id, token: msg.token})
    {:send, msg, state}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{type: :endEvent} = state) do
    Process.log(state.process, %Log.EventActivated{pid: self(), id: state.id, token: msg.token})
    {:dontsend, state}
  end

  # Hold the messages until event is trigerred
  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{activated: nil} = state) do
    Process.log(state.process, %Log.EventActivated{pid: self(), id: state.id, token: msg.token})
    {:dontsend, %{state | activated: msg}}
  end

  # If a different message comes, forget the previous one we held,
  # overwrite it with the new one (FIXME: not sure this is a good default behaviour)
  def handle_message(
        {%BPEXE.Message{token: token} = msg, _id},
        %__MODULE__{activated: %BPEXE.Message{token: token1}} = state
      )
      when token != token1 do
    Process.log(state.process, %Log.EventActivated{pid: self(), id: state.id, token: msg.token})
    {:dontsend, %{state | activated: msg}}
  end

  # When event is triggered, send the message
  def handle_info(
        {BPEXE.Signal, _id},
        %__MODULE__{type: :intermediateCatchEvent, activated: activated, incoming: [gateway]} =
          state
      )
      when not is_nil(activated) do
    Process.log(state.process, %Log.EventTrigerred{
      pid: self(),
      id: state.id,
      token: activated.token
    })

    txn = next_txn(activated)
    activated = %{activated | __txn__: txn}

    Process.log(state.process, %Log.FlowNodeForward{
      pid: self(),
      id: state.id,
      token: activated.token,
      to: state.outgoing
    })

    state =
      Enum.reduce(state.outgoing, state, fn sequence_flow, state ->
        send_message(sequence_flow, activated, state)
      end)

    save_state(txn, state)

    {:noreply, handle_completion(state)}
  end

  def handle_info({BPEXE.Signal, _id}, state) do
    {:noreply, state}
  end

  def handle_completion(%__MODULE__{type: :endEvent} = state) do
    super(state)
  end

  def handle_completion(state) do
    super(state)
  end
end
