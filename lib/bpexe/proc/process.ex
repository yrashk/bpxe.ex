defmodule BPEXE.Proc.Process do
  use GenServer

  defstruct id: nil, options: %{}, instance: nil, start_events: %{}, variables: %{}

  def start_link(id, options, instance) do
    # This way we can wait until it is initialized
    :proc_lib.start_link(__MODULE__, :init, [{id, options, instance}])
  end

  def add_event(pid, id, options, type) do
    GenServer.call(pid, {:add_event, id, options, type})
  end

  def add_task(pid, id, type, options) do
    GenServer.call(pid, {:add_task, id, type, options})
  end

  def add_sequence_flow(pid, id, options) do
    GenServer.call(pid, {:add_sequence_flow, id, options})
  end

  def add_parallel_gateway(pid, id, options) do
    GenServer.call(pid, {:add_event_based_gateway, id, options})
  end

  def add_event_based_gateway(pid, id, options) do
    GenServer.call(pid, {:add_event_based_gateway, id, options})
  end

  def start(pid) do
    start_events = GenServer.call(pid, :start_events)

    if Enum.empty?(start_events) do
      {:error, :no_start_events}
    else
      Enum.each(start_events, fn id ->
        start(pid, id)
      end)

      :ok
    end
  end

  def start(pid, id) do
    instance = GenServer.call(pid, :instance)
    event = :syn.whereis({instance, :event, :startEvent, id})
    BPEXE.Proc.Event.emit(event)
  end

  def variables(pid) do
    GenServer.call(pid, :variables)
  end

  def set_variables(pid, variables) do
    GenServer.call(pid, {:set_variables, variables})
  end

  def init({id, options, instance}) do
    :syn.register({instance, :process, id}, self())
    # Done initializing
    :proc_lib.init_ack({:ok, self()})

    :gen_server.enter_loop(__MODULE__, [], %__MODULE__{
      id: id,
      options: options,
      instance: instance
    })
  end

  def handle_call({:add_event, id, options, type}, _from, state) do
    case {type, BPEXE.Proc.Event.start_link(id, type, options, state.instance, self())} do
      {:startEvent, {:ok, pid}} ->
        {:reply, {:ok, pid}, %{state | start_events: Map.put(state.start_events, id, options)}}

      {_, {:error, err}} ->
        {:reply, {:error, err}, state}

      {_, {:ok, pid}} ->
        {:reply, {:ok, pid}, state}
    end
  end

  def handle_call({:add_task, id, type, options}, _from, state) do
    {:reply, BPEXE.Proc.Task.start_link(id, type, options, state.instance, self()), state}
  end

  def handle_call({:add_sequence_flow, id, options}, _from, state) do
    {:reply, BPEXE.Proc.SequenceFlow.start_link(id, options, state.instance, self()), state}
  end

  def handle_call({:add_parallel_gateway, id, options}, _from, state) do
    {:reply, BPEXE.Proc.ParallelGateway.start_link(id, options, state.instance, self()), state}
  end

  def handle_call({:add_event_based_gateway, id, options}, _from, state) do
    {:reply, BPEXE.Proc.EventBasedGateway.start_link(id, options, state.instance, self()), state}
  end

  def handle_call(:start_events, _from, state) do
    {:reply, Map.keys(state.start_events), state}
  end

  def handle_call(:instance, _from, state) do
    {:reply, state.instance, state}
  end

  def handle_call(:variables, _from, state) do
    {:reply, state.variables, state}
  end

  def handle_call({:set_variables, variables}, _from, state) do
    {:reply, :ok, %{state | variables: variables}}
  end
end
