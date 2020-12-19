defmodule BPXE.Engine.FlowHandler.ETS do
  alias BPXE.Engine.FlowHandler
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
  def save_state(instance, txn, instance_id, id, pid, state, %__MODULE__{pid: handler}) do
    GenServer.call(handler, {:save_state, instance, txn, instance_id, id, pid, state}, :infinity)
  end

  @impl FlowHandler
  def commit_state(instance, txn, instance_id, id, %__MODULE__{pid: handler}) do
    GenServer.call(handler, {:commit_state, instance, txn, instance_id, id}, :infinity)
  end

  @impl FlowHandler
  def restore_state(instance, instance_id, %__MODULE__{pid: handler}) do
    GenServer.call(handler, {:restore_state, instance, instance_id}, :infinity)
  end

  defmodule State do
    defstruct states: %{}, staging: nil, table: nil, last_commit: %{}, pending_commits: []
  end

  @impl GenServer
  def init(options) do
    [Set.new(options[:staging] || []), Set.new(options[:table] || [])]
    |> Result.and_then_x(fn staging, table -> {:ok, %State{staging: staging, table: table}} end)
  end

  @impl GenServer
  def handle_call(
        {:save_state, _instance, txn, instance_id, id, pid, saving_state},
        _from,
        %State{staging: staging} = state
      ) do
    Set.put(staging, {{txn, instance_id, id}, {pid, saving_state}})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, instance, {activation, txn_ctr} = txn, instance_id, id},
        from,
        %State{staging: staging, table: table, last_commit: last_commit} = state
      ) do
    last = last_commit[{instance_id, activation}]

    if is_nil(last) or last == txn_ctr - 1 do
      # if we can commit now (first transaction or a subsequent transaction in instance's activation)
      import Ex2ms

      pattern =
        fun do
          {{txn_, instance_id_, id}, {_pid, saving_state}}
          when txn_ == ^txn and instance_id_ == ^instance_id ->
            {id, saving_state}
        end

      case Set.select(staging, pattern) do
        {:ok, results} ->
          for {id, saving_state} <- results do
            Set.delete(staging, {txn, instance_id, id})
            Set.put(table, {{instance_id, id}, saving_state})
          end

          last_commit = Map.put(last_commit, {instance_id, activation}, txn_ctr)

          {:reply, :ok, %{state | last_commit: last_commit} |> next()}

        {:error, err} ->
          {:reply, {:error, err}, state}
      end
    else
      # can't commit right now
      {:noreply,
       %{
         state
         | pending_commits:
             [{from, instance, txn, instance_id, id} | state.pending_commits]
             |> Enum.sort_by(fn {_, _, txn, _, _} -> txn end)
       }}
    end
  end

  @impl GenServer
  def handle_call(
        {:restore_state, instance, instance_id},
        _from,
        %State{staging: staging, table: table} = state
      ) do
    Set.delete_all(staging)

    for {{^instance_id, id}, saved_state} <- Set.to_list!(table) do
      # FIXME: infinite timeout is not great, but a short timeout isn't great either, need to figure
      # the best way to handle it
      {_replies, _bad_pids} =
        :syn.multi_call(
          {instance, :state_recovery, id},
          {BPXE.Engine.Recoverable, :recovered_state, saved_state}
        )

      # FIXME-2: what should we do if not all replies are `ok` or there are bad pids?
    end

    {:reply, :ok, state}
  end

  defp next(%State{pending_commits: []} = state) do
    state
  end

  defp next(
         %State{
           pending_commits: [
             {from, instance, {activation, txn_ctr} = txn, instance_id, id} | rest
           ],
           last_commit: last_commit
         } = state
       ) do
    last = last_commit[{instance_id, activation}]

    if is_nil(last) or last == txn_ctr - 1 do
      # Again, this is a subsequent transaction in instance+activation, we can commit it
      case handle_call({:commit_state, instance, txn, instance_id, id}, from, %{
             state
             | pending_commits: rest
           }) do
        {:reply, response, state} ->
          GenServer.reply(from, response)
          state

        {:noreply, state} ->
          state
      end
    else
      # But if it is not, we can't
      state
    end
  end
end
