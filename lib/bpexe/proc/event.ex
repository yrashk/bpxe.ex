defmodule BPEXE.Proc.Event do
  use GenServer
  use BPEXE.Proc.Base
  use BPEXE.Proc.FlowNode
  alias BPEXE.Proc.Process
  alias BPEXE.Proc.Process.Log

  defstate([id: nil, type: nil, options: %{}, instance: nil, process: nil, activated: nil],
    persist: ~w(activated)a
  )

  def start_link(id, type, options, instance, process) do
    # This way we can wait until it is initialized
    :proc_lib.start_link(__MODULE__, :init, [{id, type, options, instance, process}])
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

    init_recoverable(state)
    # Done initializing
    :proc_lib.init_ack({:ok, self()})

    :gen_server.enter_loop(__MODULE__, [], state)
  end

  def handle_call({:add_signal_event_definition, options}, _from, state) do
    # Camunda Modeler creates signalEventDefinitions without `signalRef`, just `id`,
    # so if `signalRef` is not used, fall back to `id`.
    :syn.join({state.instance.pid, :signal, options["signalRef"] || options["id"]}, self())
    {:reply, {:ok, options}, state}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{type: :startEvent} = state) do
    {:send, msg, state}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{type: :endEvent} = state) do
    {:send, msg, state}
  end

  # Hold the messages until event is trigerred
  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{activated: nil} = state) do
    Process.log(state.process, %Log.EventActivated{pid: self(), id: state.id, token: msg.token})
    {:dontsend, %{state | activated: msg}}
  end

  # Message bounced back from the back-flow, this means this flow was chosen
  # by a gateway
  def handle_message(
        {%BPEXE.Message{token: token, __invisible__: true} = msg, _id},
        %__MODULE__{activated: %BPEXE.Message{token: token}} = state
      ) do
    Process.log(state.process, %Log.EventCompleted{pid: self(), id: state.id, token: msg.token})
    {:send, %{msg | __invisible__: false}, %{state | activated: nil}}
  end

  # If a different message comes, forget the previous one we held,
  # overwrite it with the new one (FIXME: not sure this is a good default behaviour)
  def handle_message(
        {%BPEXE.Message{token: token}, _id},
        %__MODULE__{activated: %BPEXE.Message{token: token1} = msg1} = state
      )
      when token != token1 do
    {:dontsend, %{state | activated: msg1}}
  end

  # When event is triggered, send it back to the gateway
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

    state = send_message_back(gateway, %{activated | __invisible__: true}, state)
    {:noreply, state}
  end

  def handle_info({BPEXE.Signal, _id}, state) do
    {:noreply, state}
  end

  def handle_completion(%__MODULE__{type: :endEvent} = state) do
    BPEXE.Proc.Instance.commit_state(state.instance, [state.id])
    super(state)
  end

  def handle_completion(state) do
    super(state)
  end
end
