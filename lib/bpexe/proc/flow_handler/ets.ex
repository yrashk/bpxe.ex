defmodule BPEXE.Proc.FlowHandler.ETS do
  alias BPEXE.Proc.FlowHandler
  alias ETS.Set
  @behaviour FlowHandler

  defstruct pid: nil
  use ExConstructor

  use GenServer

  def new(options \\ []) do
    result = super([])

    GenServer.start_link(__MODULE__, options)
    |> Result.map(fn pid -> %{result | pid: pid} end)
  end

  @impl FlowHandler
  def save_state(instance, instance_id, id, pid, state, %__MODULE__{pid: handler}) do
    GenServer.call(handler, {:save_state, instance, instance_id, id, pid, state}, :infinity)
  end

  @impl FlowHandler
  def commit_state(instance, instance_id, sync_ids, %__MODULE__{pid: handler}) do
    GenServer.call(handler, {:commit_state, instance, instance_id, sync_ids}, :infinity)
  end

  @impl FlowHandler
  def restore_state(instance, instance_id, %__MODULE__{pid: handler}) do
    GenServer.call(handler, {:restore_state, instance, instance_id}, :infinity)
  end

  defmodule State do
    defstruct states: %{}, staging: nil, table: nil
  end

  @impl GenServer
  def init(options) do
    [Set.new(options[:staging] || []), Set.new(options[:table] || [])]
    |> Result.and_then_x(fn staging, table -> {:ok, %State{staging: staging, table: table}} end)
  end

  @impl GenServer
  def handle_call(
        {:save_state, _instance, instance_id, id, pid, saving_state},
        _from,
        %State{staging: staging} = state
      ) do
    Set.put(staging, {{instance_id, id}, {pid, saving_state}})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, _instance, instance_id, sync_ids},
        _from,
        %State{staging: staging, table: table} = state
      ) do
    for id <- sync_ids do
      case Set.get(staging, {instance_id, id}) do
        {:ok, {_, record}} when not is_nil(record) ->
          Set.delete(staging, {instance_id, id})
          Set.put(table, {{instance_id, id}, record})

        _ ->
          :skip
      end
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(
        {:restore_state, instance, instance_id},
        _from,
        %State{staging: staging, table: table} = state
      ) do
    Set.delete_all(staging)

    for {{^instance_id, id}, {_pid, saved_state}} <- Set.to_list!(table) do
      # FIXME: infinite timeout is not great, but a short timeout isn't great either, need to figure
      # the best way to handle it
      {_replies, _bad_pids} =
        :syn.multi_call(
          {instance, :state_recovery, id},
          {BPEXE.Proc.Recoverable, :recovered_state, saved_state}
        )

      # FIXME-2: what should we do if not all replies are `ok` or there are bad pids?
    end

    {:reply, :ok, state}
  end
end
