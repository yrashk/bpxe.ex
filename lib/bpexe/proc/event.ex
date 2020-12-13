defmodule BPEXE.Proc.Event do
  use GenServer
  use BPEXE.Proc.FlowNode

  defstruct id: nil,
            type: nil,
            options: %{},
            instance: nil,
            process: nil,
            outgoing: [],
            incoming: [],
            activated: nil

  def start_link(id, type, options, instance, process) do
    # This way we can wait until it is initialized
    :proc_lib.start_link(__MODULE__, :init, [{id, type, options, instance, process}])
  end

  def add_signal_event_definition(pid, options) do
    GenServer.call(pid, {:add_signal_event_definition, options})
  end

  def emit(pid) do
    GenServer.cast(pid, :emit)
  end

  def init({id, type, options, instance, process}) do
    :syn.register({instance, :event, type, id}, self())
    # Done initializing
    :proc_lib.init_ack({:ok, self()})

    :gen_server.enter_loop(__MODULE__, [], %__MODULE__{
      id: id,
      type: type,
      options: options,
      instance: instance,
      process: process
    })
  end

  def handle_call({:add_signal_event_definition, options}, _from, state) do
    # Camunda Modeler creates signalEventDefinitions without `signalRef`, just `id`,
    # so if `signalRef` is not used, fall back to `id`.
    :syn.join({state.instance, :signal, options["signalRef"] || options["id"]}, self())
    {:reply, {:ok, options}, state}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{activated: nil} = state) do
    {:dontsend, %{state | activated: msg}}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{activated: msg} = state) do
    {:send, msg, %{state | activated: nil}}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{activated: msg1} = state) do
    {:dontsend, %{state | activated: msg}}
  end

  def handle_info(
        {BPEXE.Signal, id},
        %__MODULE__{type: :intermediateCatchEvent, activated: activated, incoming: [gateway]} =
          state
      )
      when not is_nil(activated) do
    send_message_back(gateway, activated, state)
    {:noreply, state}
  end

  def handle_info({BPEXE.Signal, id}, state) do
    {:noreply, state}
  end

  def handle_cast(:emit, state) do
    message = BPEXE.Message.new()

    for wire <- state.outgoing do
      send_message(wire, message, state)
    end

    {:noreply, state}
  end
end
