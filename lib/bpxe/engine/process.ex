defmodule BPXE.Engine.Process do
  use GenServer
  use BPXE.Engine.Base
  use BPXE.Engine.PropertyContainer
  use BPXE.Engine.Recoverable
  alias BPXE.Engine.FlowNode
  alias BPXE.Engine.Process.Log

  def start_link(attrs, model) do
    start_link([{attrs, model}])
  end

  import BPXE.Engine.BPMN

  for {element, attrs} <- BPXE.BPMN.Semantic.elements(),
      attrs["substitutionGroup"] in ["flowElement", "bpmn:flowElement"] do
    @element element
    @typ ProperCase.snake_case(element)
    @name "add_#{@typ}" |> String.to_atom()
    def unquote(@name)(pid, attrs, body \\ nil) do
      add_node(pid, @element, attrs, body)
    end
  end

  @doc """
  Convenience helper for adding and connecting sequence flow programmatically.

  Instead of having to to orchestrate `BPXE.Engine.FlowNode.add_incoming/2`,
  `BPXE.Engine.FlowNode.add_outgoing/2` and `add_sequence_flow/3`, this allows
  to do all of that in just one call.

  This reduces the amount of code that has to be written and therefore makes it
  easier to debug.

  """
  def establish_sequence_flow(server, id, source, target, attrs \\ []) do
    require OK

    OK.for do
      source_ref = BPXE.Engine.Base.id(source)
      target_ref = BPXE.Engine.Base.id(target)

      seq_flow <-
        add_sequence_flow(
          server,
          %{
            "id" => id,
            "sourceRef" => source_ref,
            "targetRef" => target_ref
          }
          |> Map.merge(attrs |> Map.new())
        )

      _out <- add_node(source, "outgoing", %{}, id)
      _in <- add_node(target, "incoming", %{}, id)
    after
      seq_flow
    end
  end

  @doc """
  Passively listen for log messages from a process. This will start delivering tokens in the following
  format:

  ```elixir
  {BPXE.Engine.Process.Log, message}
  ```

  to `subscriber` (`self()` by default). Most (if not all?) log message should be defined in
  `BPXE.Engine.Process.Log` module.

  This is particularly useful for testing, rendering visualizations, etc.

  to stop listening, call `unsubscribe_log/2`.
  """
  @spec subscribe_log(pid(), pid()) :: :ok
  @spec subscribe_log(pid()) :: :ok
  def subscribe_log(pid, subscriber \\ self()) do
    BPXE.Channel.join({pid, :log}, subscriber)
  end

  @doc """
  Stop receiving passive log messages from a process (initiated by `subscribe_logs/2`). If you were not listening
  originally, it will return `{:error, :not_listening}`. Otherwise, it will return `:ok`.
  """
  @spec unsubscribe_log(pid()) :: :ok | {:error, term}
  @spec unsubscribe_log(pid(), pid()) :: :ok | {:error, term}
  def unsubscribe_log(pid, subscriber \\ self()) do
    BPXE.Channel.leave({pid, :log}, subscriber)
    |> Result.map_error(fn :not_in_group -> :not_listening end)
  end

  @doc """
  Publishes a process log to listeners.
  """
  @spec log(pid(), term()) :: :ok
  def log(pid, log) do
    BPXE.Channel.publish({pid, :log}, {BPXE.Engine.Process.Log, log})
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
    model = GenServer.call(pid, :model)
    event = BPXE.Registry.whereis({model.pid, :event, :startEvent, id})
    token = BPXE.Token.new(activation: new_activation(pid))
    send(event, {token, nil})
    :ok
  end

  def synthesize(pid) do
    GenServer.call(pid, :synthesize)
  end

  def flow_nodes(pid) do
    GenServer.call(pid, :flow_nodes)
  end

  def id(pid) do
    GenServer.call(pid, :id)
  end

  def new_activation(pid) do
    GenServer.call(pid, :new_activation)
  end

  def activations(pid) do
    GenServer.call(pid, :activations)
  end

  alias ETS.Set

  def sequence_flows(pid) do
    # We're doing this so that sequence flows can be accessed by flow nodes
    # without blocking Process
    {_pid, meta} = BPXE.Registry.whereis({__MODULE__, pid}, meta: true)
    sequence_flows = meta[:sequence_flows]
    Set.to_list!(sequence_flows) |> Map.new()
  end

  def data_object(pid, name) do
    # We're doing this so that data objects can be accessed by other processes
    # without blocking Process
    {_pid, meta} = BPXE.Registry.whereis({__MODULE__, pid}, meta: true)
    data_objects = meta[:data_objects]

    Set.get(data_objects, name)
    |> Result.and_then(fn
      nil ->
        {:error, :not_found}

      {_, %BPXE.Engine.DataObject{} = value} ->
        {:ok, value}

      {_, %BPXE.Engine.DataObjectReference{attrs: %{"dataObjectRef" => ref}}} ->
        data_object(pid, ref)
    end)
  end

  def update_data_object(pid, %BPXE.Engine.DataObject{} = object, token \\ nil) do
    GenServer.call(pid, {:update_data_object, object, token})
  end

  def data_object_reference(pid, name) do
    # We're doing this so that data objects can be accessed by other processes
    # without blocking Process
    {_pid, meta} = BPXE.Registry.whereis({__MODULE__, pid}, meta: true)
    data_objects = meta[:data_objects]

    Set.get(data_objects, name)
    |> Result.and_then(fn
      nil ->
        {:error, :not_found}

      {_, %BPXE.Engine.DataObject{}} ->
        {:error, :not_found}

      {_, %BPXE.Engine.DataObjectReference{} = value} ->
        {:ok, value}
    end)
  end

  defstate start_events: %{},
           activations: [],
           flow_nodes: [],
           sequence_flows: nil,
           data_objects: nil

  def init({attrs, model}) do
    sequence_flows = Set.new!()
    data_objects = Set.new!()
    BPXE.Registry.register({model.pid, :process, attrs["id"]})

    BPXE.Registry.register({__MODULE__, self()},
      sequence_flows: sequence_flows,
      data_objects: data_objects
    )

    state =
      %__MODULE__{sequence_flows: sequence_flows, data_objects: data_objects}
      |> put_state(BPXE.Engine.Base, %{attrs: attrs, model: model})
      |> initialize()

    # Done initializing
    init_ack()
    enter_loop(state)
  end

  defp start_flow_node(
         module,
         args,
         %__MODULE__{} = state
       ) do
    case apply(module, :start_link, args) do
      {:ok, pid} ->
        {:reply, {:ok, pid},
         %{
           state
           | flow_nodes: [{pid, module} | state.flow_nodes]
         }}

      {:error, err} ->
        {:reply, {:error, err}, state}
    end
  end

  defp add_flow_element(_ref, "sequenceFlow", attrs, state) do
    Set.put!(state.sequence_flows, {attrs["id"], attrs})
    {:reply, {:ok, {self(), {:sequenceFlow, attrs["id"]}}}, state}
  end

  defp add_flow_element({:sequenceFlow, id}, "conditionExpression", attrs, state) do
    {_, sf} = Set.get!(state.sequence_flows, id)
    Set.put!(state.sequence_flows, {id, put_in(sf[:conditionExpression], {attrs, nil})})

    {:reply, {:ok, {self(), {:conditionExpression, id}}}, state}
  end

  @env Mix.env()

  defp add_flow_element(_ref, element, attrs, state) do
    base_state = get_state(state, BPXE.Engine.Base)

    module =
      cond do
        String.ends_with?(element, "Task") ->
          BPXE.Engine.Task

        String.ends_with?(element, "Event") ->
          BPXE.Engine.Event

        @env == :test and element == "flowNode" ->
          # Special case for testing custom flow nodes
          module_name = attrs[:module]
          Code.ensure_loaded(module_name)
          module_name

        element in Map.keys(BPXE.BPMN.Semantic.elements()) ->
          # the check above ensures `element` can't be arbitrary and blow up
          # the atom table
          module_name = "Elixir.BPXE.Engine.#{Macro.camelize(element)}" |> String.to_atom()

          Code.ensure_loaded(module_name)

          if function_exported?(module_name, :__info__, 1) do
            module_name
          else
            # FIXME: this will crash. how should we handle this?
            BPXE.Engine.FlowNode
          end
      end

    state =
      case element do
        "startEvent" ->
          put_in(state.start_events[attrs["id"]], attrs)

        _ ->
          state
      end

    args = [element, attrs, base_state.model, self()]

    start_flow_node(
      module,
      args,
      state
    )
  end

  def complete_flow_element({:conditionExpression, id}, body, state) do
    {_, sf} = Set.get!(state.sequence_flows, id)
    {attrs, _} = sf[:conditionExpression]
    Set.put!(state.sequence_flows, {id, %{sf | conditionExpression: {attrs, body}}})

    {:reply, :ok, state}
  end

  def complete_flow_element(_ref, _body, state) do
    {:reply, :ok, state}
  end

  def handle_call(:start_events, _from, state) do
    {:reply, Map.keys(state.start_events), state}
  end

  def handle_call(:synthesize, from, state) do
    nodes = state.flow_nodes

    spawn(fn ->
      for {node, _} <- nodes do
        FlowNode.synthesize(node)
      end

      GenServer.reply(from, :ok)
    end)

    {:noreply, process_state(state)}
  end

  def handle_call(:flow_nodes, _from, state) do
    {:reply, state.flow_nodes, state}
  end

  def handle_call(:new_activation, _from, state) do
    base_state = get_state(state, BPXE.Engine.Base)

    activation =
      BPXE.Engine.Process.Activation.new(
        model_id: base_state.model.id,
        process_id: base_state.attrs["id"]
      )

    log(self(), %Log.NewProcessActivation{
      id: base_state.attrs["id"],
      pid: self(),
      activation: activation
    })

    {:reply, activation, %{state | activations: [activation | state.activations]}}
  end

  def handle_call(:activations, _from, state) do
    {:reply, state.activations, state}
  end

  def handle_call({:add_node, _ref, "dataObject", attrs}, _from, state) do
    result =
      Set.put(state.data_objects, {attrs["id"], BPXE.Engine.DataObject.new(attrs: attrs)})
      |> Result.map(fn _ ->
        {self(), {:dataObject, attrs["id"]}}
      end)

    {:reply, result, state}
  end

  def handle_call({:add_node, {:dataObject, id}, "dataState", attrs}, _from, state) do
    response =
      case Set.get(state.data_objects, id) do
        {:ok, {_, data_object}} ->
          Set.put(state.data_objects, {id, %{data_object | state: attrs["name"]}})
          {:ok, {self(), {:dataObjectState, id}}}

        {:ok, nil} ->
          {:error, :data_object_not_found}

        {:error, err} ->
          {:error, err}
      end

    {:reply, response, state}
  end

  def handle_call({:add_node, _ref, "dataObjectReference", attrs}, _from, state) do
    result =
      Set.put(
        state.data_objects,
        {attrs["id"], BPXE.Engine.DataObjectReference.new(attrs: attrs)}
      )
      |> Result.map(fn _ ->
        {self(), {:dataObject, attrs["id"]}}
      end)

    {:reply, result, state}
  end

  def handle_call({:add_node, ref, element, attrs}, _from, state) do
    add_flow_element(
      ref,
      element,
      attrs,
      state
    )
  end

  def handle_call({:complete_node, ref, body}, _from, state) do
    complete_flow_element(ref, body, state)
  end

  def handle_call({:update_data_object, %BPXE.Engine.DataObject{} = object, token}, _from, state) do
    Set.put(state.data_objects, {object.attrs["id"], object})

    if token do
      base_state = get_state(state, BPXE.Engine.Base)

      BPXE.Engine.Model.save_state(
        base_state.model,
        token.__generation__,
        base_state.attrs["id"],
        self(),
        %{
          data_objects: Set.to_list!(state.data_objects)
        }
      )
    end

    {:reply, :ok, state}
  end

  # This is to avoid a warning from Base adding a catch-all clause
  @complete_node_catch_all true

  defp process_state(state) do
    state
    |> synthesize_event_based_gateways()
  end

  defp synthesize_event_based_gateways(state) do
    nodes =
      for {node, BPXE.Engine.EventBasedGateway} <- state.flow_nodes do
        node
      end

    Enum.reduce(nodes, state, &synthesize_event_based_gateway/2)
  end

  defp synthesize_event_based_gateway(node, state) do
    gateway_outgoing = FlowNode.get_outgoing(node)
    gateway_id = BPXE.Engine.Base.id(node)

    all_nodes = state.flow_nodes

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
      # We need to sort events by the order of outgoing sequence flows
      # in the event-based gateway as we later need to wire precedence gateway
      # in the same order
      |> Enum.sort_by(fn event ->
        [incoming | _] = FlowNode.get_incoming(event)
        Enum.find_index(gateway_outgoing, &(&1 == incoming))
      end)

    base_state = get_state(state, BPXE.Engine.Base)

    Enum.reduce(events, state, fn event, acc ->
      event_id = BPXE.Engine.Base.id(event)
      [event_outgoing | _] = FlowNode.get_outgoing(event)
      FlowNode.clear_outgoing(event)

      {_, event_original_sequence_flow} = Set.get!(acc.sequence_flows, event_outgoing)

      {acc, gateway} =
        case FlowNode.whereis(base_state.model.pid, precedence_gateway_id) do
          nil ->
            {:reply, {:ok, gateway}, acc} =
              handle_call(
                {:add_node, nil, "precedenceGateway", %{"id" => precedence_gateway_id}},
                :ignored,
                acc
              )

            {acc, gateway}

          pid when is_pid(pid) ->
            {acc, pid}
        end

      event_sequence_flow_id = {:synthesized_sequence_flow, {:in, event_outgoing}}

      {:reply, _, acc} =
        handle_call(
          {:add_node, nil, "sequenceFlow",
           %{
             "id" => event_sequence_flow_id,
             "sourceRef" => event_id,
             "targetRef" => precedence_gateway_id
           }},
          :ignored,
          acc
        )

      FlowNode.add_outgoing(event, %{}, event_sequence_flow_id)
      FlowNode.add_incoming(gateway, %{}, event_sequence_flow_id)

      gateway_sequence_flow_id = {:synthesized_sequence_flow, {:out, event_outgoing}}

      target_id = event_original_sequence_flow["targetRef"]

      {:reply, _, acc} =
        handle_call(
          {:add_node, nil, "sequenceFlow",
           %{
             "id" => gateway_sequence_flow_id,
             "sourceRef" => precedence_gateway_id,
             "targetRef" => target_id
           }},
          :ignored,
          acc
        )

      target = FlowNode.whereis(base_state.model.pid, target_id)
      FlowNode.remove_incoming(target, event_outgoing)

      FlowNode.add_incoming(target, %{}, gateway_sequence_flow_id)
      FlowNode.add_outgoing(gateway, %{}, gateway_sequence_flow_id)

      acc
    end)
  end
end
