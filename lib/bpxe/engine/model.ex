defmodule BPXE.Engine.Model do
  use GenServer

  defmodule Config do
    defstruct flow_handler: nil, pid: nil, init_fn: nil, id: nil
    use ExConstructor
  end

  def start_link(config \\ []) do
    # Model identification has a little bit of an unusual twist.
    # We typically identify model by either:
    # 1. Model PID
    # 2. Model ID (can be supplied as `id` option or will be automatically generated)
    #
    # Why two? The (somewhat convoluted) thinking behind this is the following:
    #
    # Model ID is a "permanent" ID that survives restarts. Therefore, things like
    # flow handlers that store and restore states should use this permanent IDs to identify
    # their records.
    #
    # Model PID is transient and will be changed at every restart, so we don't use this
    # for restarts. However, it *is* used as a component of `syn` pub/sub groups to identify this
    # particular worker of the model so that there is no chance these can be mixed up and wrong
    # tokens get to wrong groups at a wrong time.
    #
    # FIXME: is this thinking sound or am I over-engineering here?
    config = Config.new(config)
    config = %{config | id: config.id || generate_id()}

    case GenServer.start_link(__MODULE__, config) do
      {:ok, pid} ->
        GenServer.call(pid, :notify_when_initialized)
        {:ok, pid}

      error ->
        error
    end
  end

  import BPXE.Engine.BPMN

  for {element, attrs} <- BPXE.BPMN.Semantic.elements(),
      attrs["substitutionGroup"] == "rootElement" do
    @element element
    @typ ProperCase.snake_case(element)
    @name "add_#{@typ}" |> String.to_atom()
    def unquote(@name)(pid, attrs, body \\ nil) do
      add_node(pid, @element, attrs, body)
    end
  end

  def processes(pid) do
    GenServer.call(pid, :processes)
  end

  def provision_processes(pid) do
    processes = processes(pid)

    if Enum.empty?(processes) do
      {:error, :no_processes}
    else
      Enum.map(processes, fn id ->
        {id, provision_process(pid, id)}
      end)
    end
  end

  def provision_process(pid, process_id) do
    GenServer.call(pid, {:provision_process, process_id})
  end

  def start(pid) do
    processes = processes(pid)

    if Enum.empty?(processes) do
      {:error, :no_processes}
    else
      Enum.map(processes, fn id ->
        {id, start(pid, id)}
      end)
    end
  end

  def start(pid, process_id) do
    case BPXE.Registry.whereis({pid, :process, process_id}) do
      nil ->
        provision_process(pid, process_id)
        start(pid, process_id)

      process ->
        BPXE.Engine.Process.start(process)
    end
  end

  def synthesize(pid) do
    for process <- processes(pid) do
      pid = BPXE.Registry.whereis({pid, :process, process})
      BPXE.Engine.Process.synthesize(pid)
    end
  end

  def config(pid) do
    GenServer.call(pid, :config)
  end

  def model(pid) do
    GenServer.call(pid, :model)
  end

  def register_service(pid, name, service) do
    BPXE.Registry.register({BPXE.Service, pid, name}, service)
    BPXE.Service.registered(service, pid, name)
  end

  def call_service(pid, name, request, timeout \\ nil) do
    case find_service(pid, name) do
      nil -> nil
      service -> BPXE.Service.call(service, request, pid, timeout)
    end
  end

  def find_service(pid, name) do
    BPXE.Registry.whereis({BPXE.Service, pid, name})
  end

  def save_state(%Config{flow_handler: nil}, _generation, _id, _pid, _state) do
    :ok
  end

  def save_state(
        %Config{flow_handler: handler, pid: model, id: model_id},
        generation,
        id,
        pid,
        state
      )
      when is_atom(handler) do
    handler.save_state(model, generation, model_id, id, pid, state, nil)
  end

  def save_state(
        %Config{flow_handler: %{__struct__: handler} = config, pid: model, id: model_id},
        generation,
        id,
        pid,
        state
      ) do
    handler.save_state(model, generation, model_id, id, pid, state, config)
  end

  def save_state(model, generation, id, pid, state) when is_pid(pid) do
    model |> config() |> save_state(generation, id, pid, state)
  end

  def commit_state(%Config{flow_handler: nil}, _generation, _id) do
    :ok
  end

  def commit_state(
        %Config{flow_handler: handler, pid: model, id: model_id},
        generation,
        id
      )
      when is_atom(handler) do
    handler.commit_state(model, model_id, generation, id, nil)
  end

  def commit_state(
        %Config{flow_handler: %{__struct__: handler} = config, pid: model, id: model_id},
        generation,
        id
      ) do
    handler.commit_state(model, generation, model_id, id, config)
  end

  def commit_state(model, generation, id) when is_pid(model) do
    model |> config() |> commit_state(generation, id)
  end

  def restore_state(%Config{flow_handler: nil}) do
    {:error, :no_flow_handler}
  end

  def restore_state(%Config{
        flow_handler: %{__struct__: handler} = config,
        pid: model,
        id: model_id
      }) do
    if function_exported?(handler, :restore_state, 3) do
      handler.restore_state(model, model_id, config)
    else
      {:error, :not_supported}
    end
  end

  def restore_state(model) when is_pid(model) do
    model |> config() |> restore_state()
  end

  defstruct config: %{}, notify_when_initialized: nil, model: %{}

  def init(config) do
    {:ok, %__MODULE__{config: %{config | pid: self()}}, {:continue, :init_fn}}
  end

  def handle_continue(:init_fn, state) do
    pid = self()

    spawn_link(fn ->
      (state.config.init_fn || fn _ -> :ok end).(pid)
      GenServer.cast(pid, :initialized)
    end)

    {:noreply, state}
  end

  def handle_call(
        :notify_when_initialized,
        _from,
        %__MODULE__{notify_when_initialized: :done} = state
      ) do
    {:reply, :ok, state}
  end

  def handle_call(:notify_when_initialized, from, state) do
    {:noreply, %{state | notify_when_initialized: from}}
  end

  def handle_call(:processes, _from, state) do
    processes =
      for {{:info, _ref}, {"process", %{"id" => id}, _body}} <- state.model do
        id
      end

    {:reply, processes, state}
  end

  def handle_call(:config, _from, state) do
    {:reply, state.config, state}
  end

  def handle_call(:model, _from, state) do
    {:reply, build_model(state.model), state}
  end

  def handle_call({:provision_process, id}, _from, state) do
    matching_processes =
      for {{:info, ref}, {"process", %{"id" => ^id} = attrs, _body}} <- state.model do
        {ref, attrs}
      end

    case matching_processes do
      [{ref, attrs} | _] ->
        case BPXE.Engine.Process.start_link(attrs, state.config) do
          {:ok, pid} ->
            {:reply, execute_model(ref, {:ok, pid}, pid, state), state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      _ ->
        {:reply, {:error, :process_not_found}, state}
    end
  end

  def handle_call({:id, ref}, _from, state) do
    {_, %{"id" => id}, _} = state.model[{:info, ref}]
    {:reply, id, state}
  end

  def handle_call({:add_node, ref, element, attrs}, _from, state) do
    reference = make_ref()
    record = {element, attrs, nil}

    state =
      update_in(state.model[ref], fn
        nil -> [reference]
        list -> [reference | list]
      end)

    state = put_in(state.model[{:info, reference}], record)

    {:reply, {:ok, {self(), reference}}, state}
  end

  def handle_call({:add_json, ref, json}, _from, state) do
    reference = make_ref()
    record = {:json, %{}, json}

    state =
      update_in(state.model[ref], fn
        nil -> [reference]
        list -> [reference | list]
      end)

    state = put_in(state.model[{:info, reference}], record)

    {:reply, {:ok, {self(), reference}}, state}
  end

  def handle_call({:complete_node, ref, body}, _from, state) do
    state =
      update_in(state.model[{:info, ref}], fn {element, attrs, _} -> {element, attrs, body} end)

    {:reply, :ok, state}
  end

  def handle_cast(:initialized, state) do
    if state.notify_when_initialized do
      GenServer.reply(state.notify_when_initialized, :ok)
    end

    {:noreply, %{state | notify_when_initialized: :done}}
  end

  defp execute_model(ref, result, pid, state) do
    Enum.reduce((state.model[ref] || []) |> Enum.reverse(), result, fn
      _, {:error, _} = error ->
        error

      ref_, acc ->
        {element, attrs, body} = state.model[{:info, ref_}]

        result =
          if element == :json do
            add_json(pid, body)
          else
            add_node(pid, element, attrs, body)
          end

        case result do
          {:error, reason} ->
            {:error, {{element, attrs}, reason}}

          {:ok, pid_} ->
            execute_model(ref_, acc, pid_, state)

          :ok ->
            acc
        end
    end)
  end

  defp generate_id() do
    {m, f, a} = Application.get_env(:bpxe, :spec_id_generator)
    apply(m, f, a)
  end

  defp build_model(model) do
    build_model(model, nil, %{})
  end

  defp build_model(model, nil, map) do
    for ref <- Enum.reverse(model[nil] || []), reduce: map do
      acc -> Map.merge(acc, build_model(model, ref, map))
    end
  end

  defp build_model(model, key, map) do
    {element, attrs, body} = model[{:info, key}]
    attrs = put_in(attrs[:body], body)

    map =
      update_in(map[element], fn
        nil ->
          attrs

        list when is_list(list) ->
          list ++ [attrs]

        attrs1 ->
          [attrs1, attrs]
      end)

    for ref <- Enum.reverse(model[key] || []), reduce: map do
      acc -> put_in(acc[element], Map.merge(acc[element], build_model(model, ref, acc[element])))
    end
  end
end
