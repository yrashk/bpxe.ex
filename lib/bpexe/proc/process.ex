defmodule BPEXE.Proc.Process do
  use GenServer
  use BPEXE.Proc.Base
  use BPEXE.Proc.Recoverable

  def start_link(id, options, instance) do
    start_link([{id, options, instance}])
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

  to stop listening, call `unsubscribe_log/2`.
  """
  @spec subscribe_log(pid(), pid()) :: :ok
  @spec subscribe_log(pid()) :: :ok
  def subscribe_log(pid, subscriber \\ self()) do
    :syn.join({pid, :log_log}, subscriber)
  end

  @doc """
  Stop receiving passive log messages from a process (initiated by `subscribe_logs/2`). If you were not listening
  originally, it will return `{:error, :not_listening}`. Otherwise, it will return `:ok`.
  """
  @spec unsubscribe_log(pid()) :: :ok | {:error, term}
  @spec unsubscribe_log(pid(), pid()) :: :ok | {:error, term}
  def unsubscribe_log(pid, subscriber \\ self()) do
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
    event = :syn.whereis({instance.pid, :event, :startEvent, id})
    msg = BPEXE.Message.new()
    send(event, {msg, nil})
    :ok
  end

  def variables(pid) do
    GenServer.call(pid, :variables)
  end

  def set_variables(pid, variables) do
    GenServer.call(pid, {:set_variables, variables})
  end

  def id(pid) do
    GenServer.call(pid, :id)
  end

  defstruct id: nil,
            options: %{},
            instance: nil,
            start_events: %{},
            variables: %{},
            pending_sequence_flows: %{}

  def init({id, options, instance}) do
    :syn.register({instance.pid, :process, id}, self())

    state = %__MODULE__{
      id: id,
      options: options,
      instance: instance
    }

    state = initialize(state)
    # Done initializing
    init_ack()
    enter_loop(state)
  end

  defp start_flow_node(
         module,
         id,
         args,
         %__MODULE__{pending_sequence_flows: pending_sequence_flows} = state
       ) do
    result =
      apply(module, :start_link, args)
      |> Result.map(fn pid ->
        if options = pending_sequence_flows[id] do
          BPEXE.Proc.FlowNode.add_sequence_flow(pid, id, options)
        end

        pid
      end)

    {:reply, result,
     %{state | pending_sequence_flows: Map.delete(state.pending_sequence_flows, id)}}
  end

  def handle_call({:add_event, id, options, type}, _from, state) do
    case {type,
          start_flow_node(
            BPEXE.Proc.Event,
            id,
            [id, type, options, state.instance, self()],
            state
          )} do
      {:startEvent, {:reply, result, state}} ->
        {:reply, result, %{state | start_events: Map.put(state.start_events, id, options)}}

      {_, {:reply, result, state}} ->
        {:reply, result, state}
    end
  end

  def handle_call({:add_task, id, type, options}, _from, state) do
    start_flow_node(BPEXE.Proc.Task, id, [id, type, options, state.instance, self()], state)
  end

  def handle_call({:add_sequence_flow, id, options}, _from, state) do
    case :syn.whereis({state.instance.pid, :flow_node, options["sourceRef"]}) do
      pid when is_pid(pid) ->
        BPEXE.Proc.FlowNode.add_sequence_flow(pid, id, options)
        {:reply, {:ok, id}, state}

      :undefined ->
        {:reply, {:ok, id},
         %{
           state
           | pending_sequence_flows:
               Map.put(state.pending_sequence_flows, options["sourceRef"], options)
         }}
    end
  end

  def handle_call({:add_parallel_gateway, id, options}, _from, state) do
    start_flow_node(BPEXE.Proc.ParallelGateway, id, [id, options, state.instance, self()], state)
  end

  def handle_call({:add_event_based_gateway, id, options}, _from, state) do
    start_flow_node(
      BPEXE.Proc.EventBasedGateway,
      id,
      [id, options, state.instance, self()],
      state
    )
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

  # FIXME: add txn id
  def handle_call({:set_variables, variables}, _from, state) do
    variables = Map.merge(state.variables, variables)

    if variables != state.variables do
      BPEXE.Proc.Instance.save_state(state.instance, :FIXME, state.id, self(), %{
        variables: variables
      })
    end

    {:reply, :ok, %{state | variables: variables}}
  end

  def handle_call(:id, _from, state) do
    {:reply, state.id, state}
  end
end
