defmodule BPEXE.Proc.Instance do
  use GenServer

  defmodule Config do
    defstruct flow_handler: nil, pid: nil, init_fn: nil, id: nil
    use ExConstructor
  end

  def start_link(config \\ []) do
    # Instance identification has a little bit of an unusual twist.
    # We typically identify instance by either:
    # 1. Instance PID
    # 2. Instance ID (can be supplied as `id` option or will be automatically generated)
    #
    # Why two? The (somewhat convoluted) thinking behind this is the following:
    #
    # Instance ID is a "permanent" ID that survives restarts. Therefore, things like
    # flow handlers that store and restore states should use this permanent IDs to identify
    # their records.
    #
    # Instance PID is transient and will be changed at every restart, so we don't use this
    # for restarts. However, it *is* used as a component of `syn` pub/sub groups to identify this
    # particular worker of the instance so that there is no chance these can be mixed up and wrong
    # messages get to wrong groups at a wrong time.
    #
    # FIXME: is this thinking sound or am I over-engineering here?
    config =
      Config.new(config)
      |> Map.update(:id, make_ref(), &Function.identity/1)

    case GenServer.start_link(__MODULE__, config) do
      {:ok, pid} ->
        GenServer.call(pid, :notify_when_initialized)
        {:ok, pid}

      error ->
        error
    end
  end

  def add_process(pid, id, options) do
    GenServer.call(pid, {:add_process, id, options})
  end

  def processes(pid) do
    GenServer.call(pid, :processes)
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

  def config(pid) do
    GenServer.call(pid, :config)
  end

  def save_state(%Config{flow_handler: nil}, _txn, _id, _pid, _state) do
    :ok
  end

  def save_state(
        %Config{flow_handler: handler, pid: instance, id: instance_id},
        txn,
        id,
        pid,
        state
      )
      when is_atom(handler) do
    handler.save_state(instance, txn, instance_id, id, pid, state, nil)
  end

  def save_state(
        %Config{flow_handler: %{__struct__: handler} = config, pid: instance, id: instance_id},
        txn,
        id,
        pid,
        state
      ) do
    handler.save_state(instance, txn, instance_id, id, pid, state, config)
  end

  def save_state(instance, txn, id, pid, state) when is_pid(pid) do
    instance |> config() |> save_state(txn, id, pid, state)
  end

  def commit_state(%Config{flow_handler: nil}, _txn, _id) do
    :ok
  end

  def commit_state(%Config{flow_handler: handler, pid: instance, id: instance_id}, txn, id)
      when is_atom(handler) do
    handler.commit_state(instance, instance_id, txn, id, nil)
  end

  def commit_state(
        %Config{flow_handler: %{__struct__: handler} = config, pid: instance, id: instance_id},
        txn,
        id
      ) do
    handler.commit_state(instance, txn, instance_id, id, config)
  end

  def commit_state(instance, txn, id) when is_pid(instance) do
    instance |> config() |> commit_state(txn, id)
  end

  def restore_state(%Config{flow_handler: nil}) do
    {:error, :no_flow_handler}
  end

  def restore_state(%Config{
        flow_handler: %{__struct__: handler} = config,
        pid: instance,
        id: instance_id
      }) do
    if function_exported?(handler, :restore_state, 3) do
      handler.restore_state(instance, instance_id, config)
    else
      {:error, :not_supported}
    end
  end

  def restore_state(instance) when is_pid(instance) do
    instance |> config() |> restore_state()
  end

  def start(pid, process_id) do
    process = :syn.whereis({pid, :process, process_id})
    BPEXE.Proc.Process.start(process)
  end

  defstruct config: %{}, processes: %{}, notify_when_initialized: nil

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

  def handle_call({:add_process, id, options}, _from, state) do
    case BPEXE.Proc.Process.start_link(id, options, state.config) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, %{state | processes: Map.put(state.processes, id, options)}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:processes, _from, state) do
    {:reply, Map.keys(state.processes), state}
  end

  def handle_call(:config, _from, state) do
    {:reply, state.config, state}
  end

  def handle_cast(:initialized, state) do
    if state.notify_when_initialized do
      GenServer.reply(state.notify_when_initialized, :ok)
    end

    {:noreply, %{state | notify_when_initialized: :done}}
  end
end
