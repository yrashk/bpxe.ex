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

  @doc """
  Convenience helper for adding and connecting sequence flow programmatically.

  Instead of having to to orchestrate `BPEXE.Proc.FlowNode.add_incoming/2`,
  `BPEXE.Proc.FlowNode.add_outgoing/2` and `add_sequence_flow/3`, this allows
  to do all of that in just one call.

  This reduces the amount of code that has to be written and therefore makes it
  easier to debug.

  """
  @spec establish_sequence_flow(pid(), term(), pid(), pid()) :: {:ok, pid()} | {:error, term()}
  def establish_sequence_flow(pid, id, source, target) do
    require OK

    OK.for do
      source_ref = BPEXE.Proc.Base.id(source)
      target_ref = BPEXE.Proc.Base.id(target)

      seq_flow <-
        add_sequence_flow(pid, id, %{
          "id" => id,
          "sourceRef" => source_ref,
          "targetRef" => target_ref
        })

      _out <- BPEXE.Proc.FlowNode.add_outgoing(source, id)
      _in <- BPEXE.Proc.FlowNode.add_incoming(target, id)
    after
      seq_flow
    end
  end

  def add_parallel_gateway(pid, id, options) do
    GenServer.call(pid, {:add_parallel_gateway, id, options})
  end

  def add_event_based_gateway(pid, id, options) do
    GenServer.call(pid, {:add_event_based_gateway, id, options})
  end

  @doc """
  Passively listen for log messages from a process. This will start delivering messages in the following
  format:

  ```elixir
  {BPEXE.Proc.Process.Log, message}
  ```

  to `subscriber` (`self()` by default). Most (if not all?) log messages should be defined in
  `BPEXE.Proc.Process.Log` module.

  This is particularly useful for testing, rendering visualizations, etc.

  to stop listening, call `stop_listening_log/2`.
  """
  @spec listen_log(pid(), pid()) :: :ok
  @spec listen_log(pid()) :: :ok
  def listen_log(pid, subscriber \\ self()) do
    :syn.join({pid, :log_log}, subscriber)
  end

  @doc """
  Stop receiving passive log messages from a process (initiated by `listen_logs/2`). If you were not listening
  originally, it will return `{:error, :not_listening}`. Otherwise, it will return `:ok`.
  """
  @spec stop_listening_log(pid()) :: :ok | {:error, term}
  @spec stop_listening_log(pid(), pid()) :: :ok | {:error, term}
  def stop_listening_log(pid, subscriber \\ self()) do
    :syn.leave({pid, :log_log}, subscriber)
    |> Result.map_error(fn :not_in_group -> :not_listening end)
  end

  @doc """
  Publishes a process log to listeners.
  """
  @spec log(pid(), term()) :: :ok
  def log(pid, log) do
    :syn.publish({pid, :log_log}, {BPEXE.Proc.Process.Log, log})
  end

  def start(pid) do
    start_events = GenServer.call(pid, :start_events)

    if Enum.empty?(start_events) do
      {:error, :no_start_events}
    else
      Enum.map(start_events, fn id ->
        {id, start(pid, id)}
      end)
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
