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
  def save_state(model, generation, model_id, id, pid, state, %__MODULE__{pid: stepper}) do
    GenServer.call(
      stepper,
      {:save_state, model, generation, model_id, id, pid, state},
      :infinity
    )
  end

  @impl FlowHandler
  def commit_state(model, generation, model_id, id, %__MODULE__{pid: stepper}) do
    GenServer.call(stepper, {:commit_state, model, generation, model_id, id}, :infinity)
  end

  def continue(%__MODULE__{pid: stepper}) do
    GenServer.call(stepper, :continue, :infinity)
  end

  defmodule State do
    defstruct generations: %{},
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
        {:save_state, model, generation, model_id, id, pid, saving_state},
        _from,
        %State{} = state
      ) do
    data = {{model, id}, {id, pid, saving_state}}

    generations =
      Map.update(state.generations, {model_id, generation}, [data], fn generations ->
        [data | generations] |> Enum.uniq_by(fn {k, _} -> k end)
      end)

    {:reply, :ok, %{state | generations: generations}}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, model, {activation, generation_ctr} = generation, model_id, id},
        from,
        %State{lock: lock, last_commit: last_commit} = state
      ) do
    last = last_commit[{model_id, activation}]

    if !lock[{model_id, activation}] and (is_nil(last) or last == generation_ctr - 1) do
      # We can commit now
      data = Map.get(state.generations, {model_id, generation})
      generations = Map.delete(state.generations, {activation, generation})

      lock = Map.put(lock, {model_id, activation}, true)

      {:reply, :ok,
       %{
         state
         | lock: lock,
           committed: Map.put(state.committed, {model_id, activation}, data),
           generations: generations,
           last_commit: Map.put(state.last_commit, {model_id, activation}, generation_ctr)
       }}
    else
      # We can't commit now
      {:noreply,
       %{
         state
         | pending_commits: [
             {from, generation, model, model_id, id} | state.pending_commits
           ]
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
           | pending_commits:
               Enum.sort_by(state.pending_commits, fn {_, generation, _, _, _} -> generation end)
         }
         |> next()}

      {key, true} ->
        {:reply, Map.get(state.committed, key),
         %{
           state
           | committed: Map.delete(state.committed, key),
             pending_commits:
               Enum.sort_by(state.pending_commits, fn {_, generation, _, _, _} -> generation end),
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
             {from, {activation, generation_ctr} = generation, model, model_id, id} | rest
           ],
           last_commit: last_commit
         } = state
       ) do
    last = last_commit[{model_id, activation}]

    if is_nil(last) or last == generation_ctr - 1 do
      # We can commit now
      case handle_call({:commit_state, model, generation, model_id, id}, from, %{
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
