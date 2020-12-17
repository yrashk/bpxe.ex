defmodule BPEXE.Proc.FlowHandler.Stepper do
  alias BPEXE.Proc.FlowHandler
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
  def save_state(instance, txn, instance_id, id, pid, state, %__MODULE__{pid: stepper}) do
    GenServer.call(stepper, {:save_state, instance, txn, instance_id, id, pid, state}, :infinity)
  end

  @impl FlowHandler
  def commit_state(instance, txn, instance_id, id, %__MODULE__{pid: stepper}) do
    GenServer.call(stepper, {:commit_state, instance, txn, instance_id, id}, :infinity)
  end

  def continue(%__MODULE__{pid: stepper}) do
    GenServer.call(stepper, :continue, :infinity)
  end

  defmodule State do
    defstruct transactions: %{}, lock: false, committed: nil, pending_commits: [], last_commit: -1
  end

  @impl GenServer
  def init(_) do
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_call(
        {:save_state, instance, txn, _instance_id, id, pid, saving_state},
        _from,
        %State{} = state
      ) do
    data = {{instance, id}, {id, pid, saving_state}}

    transactions =
      Map.update(state.transactions, txn, [data], fn txns ->
        [data | txns] |> Enum.uniq_by(fn {k, _} -> k end)
      end)

    {:reply, :ok, %{state | transactions: transactions}}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, instance, txn, _instance_id, id},
        from,
        %State{lock: false, last_commit: last_commit} = state
      )
      when last_commit + 1 == txn do
    data = Map.get(state.transactions, txn)
    transactions = Map.delete(state.transactions, txn)

    {:reply, :ok,
     %{state | lock: true, committed: data, transactions: transactions, last_commit: txn}}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, instance, txn, _instance_id, id},
        from,
        %State{} = state
      ) do
    {:noreply, %{state | pending_commits: [{from, txn, instance, id} | state.pending_commits]}}
  end

  @impl GenServer
  def handle_call(:continue, _from, %State{lock: false} = state) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(
        :continue,
        _from,
        %State{} = state
      ) do
    {:reply, state.committed,
     %{
       state
       | committed: nil,
         pending_commits: Enum.sort_by(state.pending_commits, fn {_, txn, _, _} -> txn end),
         lock: false
     }
     |> next()}
  end

  defp next(
         %State{pending_commits: [{from, txn, instance, id} | rest], last_commit: last_commit} =
           state
       )
       when last_commit + 1 == txn do
    case handle_call({:commit_state, instance, txn, :ignored, id}, from, %{
           state
           | pending_commits: rest
         }) do
      {:reply, response, state} ->
        GenServer.reply(from, response)
        state

      {:noreply, state} ->
        state
    end
  end

  defp next(%State{} = state) do
    state
  end
end
