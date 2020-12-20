defmodule BPXE.Engine.FlowHandler.Stepper do
  alias BPXE.Engine.FlowHandler
  @behaviour FlowHandler

  defstruct pid: nil
  use ExConstructor

  use GenServer

  def new(options \\ []) do
    result = super(options)

    GenServer.start_link(__MODULE__, nil)
    |> Result.map(fn pid -> %{result | pid: pid} end)
  end

  @impl FlowHandler
  def save_state(blueprint, txn, blueprint_id, id, pid, state, %__MODULE__{pid: stepper}) do
    GenServer.call(stepper, {:save_state, blueprint, txn, blueprint_id, id, pid, state}, :infinity)
  end

  @impl FlowHandler
  def commit_state(blueprint, txn, blueprint_id, id, %__MODULE__{pid: stepper}) do
    GenServer.call(stepper, {:commit_state, blueprint, txn, blueprint_id, id}, :infinity)
  end

  def continue(%__MODULE__{pid: stepper}) do
    GenServer.call(stepper, :continue, :infinity)
  end

  defmodule State do
    defstruct transactions: %{},
              lock: %{},
              committed: %{},
              pending_commits: [],
              last_commit: %{}
  end

  @impl GenServer
  def init(_) do
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_call(
        {:save_state, blueprint, txn, blueprint_id, id, pid, saving_state},
        _from,
        %State{} = state
      ) do
    data = {{blueprint, id}, {id, pid, saving_state}}

    transactions =
      Map.update(state.transactions, {blueprint_id, txn}, [data], fn txns ->
        [data | txns] |> Enum.uniq_by(fn {k, _} -> k end)
      end)

    {:reply, :ok, %{state | transactions: transactions}}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, blueprint, {activation, txn_ctr} = txn, blueprint_id, id},
        from,
        %State{lock: lock, last_commit: last_commit} = state
      ) do
    last = last_commit[{blueprint_id, activation}]

    if !lock[{blueprint_id, activation}] and (is_nil(last) or last == txn_ctr - 1) do
      # We can commit now
      data = Map.get(state.transactions, {blueprint_id, txn})
      transactions = Map.delete(state.transactions, {activation, txn})

      lock = Map.put(lock, {blueprint_id, activation}, true)

      {:reply, :ok,
       %{
         state
         | lock: lock,
           committed: Map.put(state.committed, {blueprint_id, activation}, data),
           transactions: transactions,
           last_commit: Map.put(state.last_commit, {blueprint_id, activation}, txn_ctr)
       }}
    else
      # We can't commit now
      {:noreply,
       %{
         state
         | pending_commits: [{from, txn, blueprint, blueprint_id, id} | state.pending_commits]
       }}
    end
  end

  @impl GenServer
  def handle_call(
        :continue,
        _from,
        %State{} = state
      ) do
    case Enum.find(state.lock, fn {_key, locked} -> locked end) do
      nil ->
        # There was nothing yet

        {:reply, :ok,
         %{
           state
           | pending_commits: Enum.sort_by(state.pending_commits, fn {_, txn, _, _, _} -> txn end)
         }
         |> next()}

      {key, true} ->
        {:reply, Map.get(state.committed, key),
         %{
           state
           | committed: Map.delete(state.committed, key),
             pending_commits:
               Enum.sort_by(state.pending_commits, fn {_, txn, _, _, _} -> txn end),
             lock: Map.put(state.lock, key, false)
         }
         |> next()}
    end
  end

  defp next(%State{pending_commits: []} = state) do
    state
  end

  defp next(
         %State{
           pending_commits: [
             {from, {activation, txn_ctr} = txn, blueprint, blueprint_id, id} | rest
           ],
           last_commit: last_commit
         } = state
       ) do
    last = last_commit[{blueprint_id, activation}]

    if is_nil(last) or last == txn_ctr - 1 do
      # We can commit now
      case handle_call({:commit_state, blueprint, txn, blueprint_id, id}, from, %{
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
      # We can't commit now
      state
    end
  end
end
