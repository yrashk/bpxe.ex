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
  def save_state(instance, instance_id, id, pid, state, %__MODULE__{pid: stepper}) do
    GenServer.call(stepper, {:save_state, instance, instance_id, id, pid, state}, :infinity)
  end

  @impl FlowHandler
  def commit_state(instance, instance_id, sync_ids, %__MODULE__{pid: stepper}) do
    GenServer.call(stepper, {:commit_state, instance, instance_id, sync_ids}, :infinity)
  end

  def continue(%__MODULE__{pid: stepper}) do
    GenServer.call(stepper, :continue, :infinity)
  end

  defmodule State do
    defstruct states: %{}, committed: [], lock: false, pending_commits: []
  end

  @impl GenServer
  def init(_) do
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_call({:save_state, instance, _instance_id, id, pid, saving_state}, _from, state) do
    states = Map.put(state.states, {instance, id}, {id, pid, saving_state})
    {:reply, :ok, %{state | states: states}}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, instance, _instance_id, sync_ids},
        from,
        %State{lock: true} = state
      ) do
    {:noreply,
     %{state | pending_commits: [{from, instance, sync_ids} | state.pending_commits]}}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, instance, _instance_id, sync_ids},
        _from,
        %State{lock: false} = state
      ) do
    {:reply, :ok, commit(instance, sync_ids, state)}
  end

  @impl GenServer
  def handle_call(:continue, _from, %State{committed: [], pending_commits: []} = state) do
    {:reply, :ok, %{state | lock: false}}
  end

  @impl GenServer
  def handle_call(
        :continue,
        _from,
        %State{committed: [], pending_commits: [{from, instance, sync_ids} | rest]} = state
      ) do
    state = commit(instance, sync_ids, state)
    GenServer.reply(from, :ok)
    handle_call(:continue, from, %{state | pending_commits: rest})
  end

  @impl GenServer
  def handle_call(:continue, _from, %State{committed: committed} = state) do
    {:reply, committed, %{state | committed: [], lock: true}}
  end

  defp commit(instance, sync_ids, state) do
    {committed, states} =
      Enum.reduce(sync_ids, {[], state.states}, fn id, {acc, map} ->
        c = state.states[{instance, id}]
        {if(c, do: [c | acc], else: acc), Map.delete(map, {instance, id})}
      end)

    %{state | states: states, committed: committed ++ state.committed, lock: true}
  end
end
