defmodule BPXE.Engine.Process do
  use GenServer
  use BPXE.Engine.Base
  use BPXE.Engine.Recoverable
  alias BPXE.Engine.FlowNode

  def start_link(id, options, instance) do
    start_link([{id, options, instance}])
  end

  def add_event(pid, id, type, options) do
    GenServer.call(pid, {:add_event, id, type, options})
  end

  def add_task(pid, id, type, options) do
    GenServer.call(pid, {:add_task, id, type, options})
  end

  def add_sequence_flow(pid, id, options) do
    GenServer.call(pid, {:add_sequence_flow, id, options})
  end

  @doc """
  Convenience helper for adding and connecting sequence flow programmatically.

  Instead of having to to orchestrate `BPXE.Engine.FlowNode.add_incoming/2`,
  `BPXE.Engine.FlowNode.add_outgoing/2` and `add_sequence_flow/3`, this allows
  to do all of that in just one call.

  This reduces the amount of code that has to be written and therefore makes it
  easier to debug.

  """
  @spec establish_sequence_flow(pid(), term(), pid(), pid()) :: {:ok, pid()} | {:error, term()}
  @spec establish_sequence_flow(pid(), term(), pid(), pid(), Map.t() | [term]) ::
          {:ok, pid()} | {:error, term()}
  def establish_sequence_flow(pid, id, source, target, options \\ []) do
    require OK

    OK.for do
      source_ref = BPXE.Engine.Base.id(source)
      target_ref = BPXE.Engine.Base.id(target)

      seq_flow <-
        add_sequence_flow(
          pid,
          id,
          %{
            "id" => id,
            "sourceRef" => source_ref,
            "targetRef" => target_ref
          }
          |> Map.merge(options |> Map.new())
        )

      _out <- FlowNode.add_outgoing(source, id)
      _in <- FlowNode.add_incoming(target, id)
    after
      seq_flow
    end
  end

  def add_exclusive_gateway(pid, id, options) do
    GenServer.call(pid, {:add_exclusive_gateway, id, options})
  end

  def add_parallel_gateway(pid, id, options) do
    GenServer.call(pid, {:add_parallel_gateway, id, options})
  end

  def add_inclusive_gateway(pid, id, options) do
    GenServer.call(pid, {:add_inclusive_gateway, id, options})
  end

  def add_event_based_gateway(pid, id, options) do
    GenServer.call(pid, {:add_event_based_gateway, id, options})
  end

  @doc """
  Adds Precedence Gateway (`BPXE.Engine.PrecedenceGateway`). Please note that this is not a standard gateway.
  """
  def add_precedence_gateway(pid, id, options) do
    GenServer.call(pid, {:add_precedence_gateway, id, options})
  end

  @doc """
  Adds Sensor Gateway (`BPXE.Engine.SensorGateway`). Please note that this is not a standard gateway.
  """
  def add_sensor_gateway(pid, id, options) do
    GenServer.call(pid, {:add_sensor_gateway, id, options})
  end

  @doc """
  Passively listen for log messages from a process. This will start delivering messages in the following
  format:

  ```elixir
  {BPXE.Engine.Process.Log, message}
  ```

  to `subscriber` (`self()` by default). Most (if not all?) log messages should be defined in
  `BPXE.Engine.Process.Log` module.

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
    :syn.publish({pid, :log_log}, {BPXE.Engine.Process.Log, log})
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
    synthesize(pid)
    instance = GenServer.call(pid, :instance)
    event = :syn.whereis({instance.pid, :event, :startEvent, id})
    msg = BPXE.Message.new()
    send(event, {msg, nil})
    :ok
  end

  def synthesize(pid) do
    GenServer.call(pid, :synthesize)
  end

  def flow_nodes(pid) do
    GenServer.call(pid, :flow_nodes)
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
            pending_sequence_flows: %{},
            intermediate_catch_events: %{}

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
          FlowNode.add_sequence_flow(pid, id, options)
        end

        pid
      end)

    {:reply, result,
     %{state | pending_sequence_flows: Map.delete(state.pending_sequence_flows, id)}}
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
      BPXE.Engine.Instance.save_state(state.instance, :FIXME, state.id, self(), %{
        variables: variables
      })
    end

    {:reply, :ok, %{state | variables: variables}}
  end

  def handle_call(:id, _from, state) do
    {:reply, state.id, state}
  end

  def handle_call(:synthesize, from, state) do
    nodes = flow_nodes()

    spawn(fn ->
      for {node, _} <- nodes do
        FlowNode.synthesize(node)
      end

      GenServer.reply(from, :ok)
    end)

    {:noreply, process_state(state)}
  end

  def handle_call(:flow_nodes, _from, state) do
    {:reply, flow_nodes(), state}
  end

  def handle_call(operation, from, state) do
    handle_call_internal(operation, from, state)
  end

  defp handle_call_internal({:add_event, id, type, options}, _from, state) do
    case {type,
          start_flow_node(
            BPXE.Engine.Event,
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

  defp handle_call_internal({:add_task, id, type, options}, _from, state) do
    start_flow_node(BPXE.Engine.Task, id, [id, type, options, state.instance, self()], state)
  end

  defp handle_call_internal({:add_sequence_flow, id, options}, _from, state) do
    case :syn.whereis({state.instance.pid, :flow_node, options["sourceRef"]}) do
      pid when is_pid(pid) ->
        {:reply, {:ok, FlowNode.add_sequence_flow(pid, id, options)}, state}

      :undefined ->
        {:reply, {:ok, id},
         %{
           state
           | pending_sequence_flows:
               Map.put(state.pending_sequence_flows, options["sourceRef"], options)
         }}
    end
  end

  defp handle_call_internal({:add_exclusive_gateway, id, options}, _from, state) do
    start_flow_node(
      BPXE.Engine.ExclusiveGateway,
      id,
      [id, options, state.instance, self()],
      state
    )
  end

  defp handle_call_internal({:add_parallel_gateway, id, options}, _from, state) do
    start_flow_node(
      BPXE.Engine.ParallelGateway,
      id,
      [id, options, state.instance, self()],
      state
    )
  end

  defp handle_call_internal({:add_inclusive_gateway, id, options}, _from, state) do
    start_flow_node(
      BPXE.Engine.InclusiveGateway,
      id,
      [id, options, state.instance, self()],
      state
    )
  end

  defp handle_call_internal({:add_event_based_gateway, id, options}, _from, state) do
    start_flow_node(
      BPXE.Engine.EventBasedGateway,
      id,
      [id, options, state.instance, self()],
      state
    )
  end

  defp handle_call_internal({:add_precedence_gateway, id, options}, _from, state) do
    start_flow_node(
      BPXE.Engine.PrecedenceGateway,
      id,
      [id, options, state.instance, self()],
      state
    )
  end

  defp handle_call_internal({:add_sensor_gateway, id, options}, _from, state) do
    start_flow_node(
      BPXE.Engine.SensorGateway,
      id,
      [id, options, state.instance, self()],
      state
    )
  end

  defp process_state(state) do
    state
    |> synthesize_event_based_gateways()
  end

  defp synthesize_event_based_gateways(state) do
    nodes =
      for {node, BPXE.Engine.EventBasedGateway} <- flow_nodes() do
        node
      end

    Enum.reduce(nodes, state, &synthesize_event_based_gateway/2)
  end

  @spec_schema BPXE.BPMN.ext_spec()
  defp synthesize_event_based_gateway(node, state) do
    gateway_outgoing = FlowNode.get_outgoing(node)
    gateway_id = BPXE.Engine.Base.id(node)

    all_nodes = flow_nodes()

    precedence_gateway_id = {:synthesized_precedence_gateway, gateway_id}

    events =
      for {event_node, BPXE.Engine.Event} <- all_nodes,
          # event with the nodes that are connected to them
          {node, _} <- all_nodes,
          BPXE.Engine.Base.id(node) != precedence_gateway_id,
          # that are connected to the above event based gateway
          event_incoming <- FlowNode.get_incoming(event_node),
          Enum.member?(gateway_outgoing, event_incoming),
          outgoing <- FlowNode.get_outgoing(event_node),
          # where connected node incoming has event's outgoing
          Enum.member?(FlowNode.get_incoming(node), outgoing) do
        # this way it's complete for synthesis
        event_node
      end

    Enum.reduce(events, state, fn event, acc ->
      event_id = BPXE.Engine.Base.id(event)
      [event_outgoing | _] = FlowNode.get_outgoing(event)
      FlowNode.clear_outgoing(event)
      event_original_sequence_flow = FlowNode.remove_sequence_flow(event, event_outgoing)

      {acc, gateway} =
        case FlowNode.whereis(state.instance.pid, precedence_gateway_id) do
          nil ->
            {:reply, {:ok, gateway}, acc} =
              handle_call_internal(
                {:add_precedence_gateway, precedence_gateway_id, %{}},
                :ignored,
                acc
              )

            {acc, gateway}

          pid when is_pid(pid) ->
            {acc, pid}
        end

      event_sequence_flow_id = {:synthesized_sequence_flow, {:in, event_outgoing}}

      FlowNode.add_sequence_flow(event, event_sequence_flow_id, %{
        "sourceRef" => event_id,
        "targetRef" => precedence_gateway_id
      })

      FlowNode.add_outgoing(event, event_sequence_flow_id)
      FlowNode.add_incoming(gateway, event_sequence_flow_id)

      gateway_sequence_flow_id = {:synthesized_sequence_flow, {:out, event_outgoing}}

      target_id = event_original_sequence_flow["targetRef"]

      FlowNode.add_sequence_flow(gateway, gateway_sequence_flow_id, %{
        "sourceRef" => precedence_gateway_id,
        "targetRef" => target_id,
        {BPXE.BPMN.ext_spec(), "correspondsTo"} => event_sequence_flow_id
      })

      target = FlowNode.whereis(state.instance.pid, target_id)
      FlowNode.remove_incoming(target, event_outgoing)

      if BPXE.Engine.Base.module(target) == BPXE.Engine.PrecedenceGateway do
        # if event's target is a precedence gateway, we need to rewrite incoming/outgoing mapping
        for {flow, %{{@spec_schema, "correspondsTo"} => ^event_outgoing} = options} <-
              FlowNode.get_sequence_flows(target) do
          FlowNode.remove_sequence_flow(target, flow)

          FlowNode.add_sequence_flow(target, flow, %{
            options
            | {BPXE.BPMN.ext_spec(), "correspondsTo"} => gateway_sequence_flow_id
          })
        end
      end

      FlowNode.add_incoming(target, gateway_sequence_flow_id)
      FlowNode.add_outgoing(gateway, gateway_sequence_flow_id)

      acc
    end)
  end

  defp flow_nodes() do
    {:links, links} = Process.info(self(), :links)

    for link <- links,
        {:dictionary, dict} = Process.info(link, :dictionary),
        module = dict[BPXE.Engine.Base],
        not is_nil(module),
        function_exported?(module, :flow_node?, 0) and apply(module, :flow_node?, []) do
      {link, module}
    end
  end
end
