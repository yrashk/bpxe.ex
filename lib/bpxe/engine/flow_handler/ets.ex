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
  def save_state(model, generation, model_id, id, pid, state, %__MODULE__{pid: handler}) do
    GenServer.call(
      handler,
      {:save_state, model, generation, model_id, id, pid, state},
      :infinity
    )
  end

  @impl FlowHandler
  def commit_state(model, generation, model_id, id, %__MODULE__{pid: handler}) do
    GenServer.call(handler, {:commit_state, model, generation, model_id, id}, :infinity)
  end

  @impl FlowHandler
  def restore_state(model, model_id, %__MODULE__{pid: handler}) do
    GenServer.call(handler, {:restore_state, model, model_id}, :infinity)
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
        {:save_state, _model, generation, model_id, id, pid, saving_state},
        _from,
        %State{staging: staging} = state
      ) do
    Set.put(staging, {{generation, model_id, id}, {pid, saving_state}})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(
        {:commit_state, model, {activation, generation_ctr} = generation, model_id, id},
        from,
        %State{staging: staging, table: table, last_commit: last_commit} = state
      ) do
    last = last_commit[{model_id, activation}]

    if is_nil(last) or last == generation_ctr - 1 do
      # if we can commit now (first generation or a subsequent generation in model's activation)
      import Ex2ms

      pattern =
        fun do
          {{generation_, model_id_, id}, {_pid, saving_state}}
          when generation_ == ^generation and model_id_ == ^model_id ->
            {id, saving_state}
        end

      case Set.select(staging, pattern) do
        {:ok, results} ->
          for {id, saving_state} <- results do
            Set.delete(staging, {generation, model_id, id})
            Set.put(table, {{model_id, id}, {saving_state, {activation, generation_ctr}}})
          end

          last_commit = Map.put(last_commit, {model_id, activation}, generation_ctr)

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
             [{from, model, generation, model_id, id} | state.pending_commits]
             |> Enum.sort_by(fn {_, _, generation, _, _} -> generation end)
       }}
    end
  end

  @impl GenServer
  def handle_call(
        {:restore_state, model, model_id},
        _from,
        %State{staging: staging, table: table} = state
      ) do
    Set.delete_all(staging)

    for {activation, ctr} <-
          Set.to_list!(table)
          |> Enum.map(fn {_, {_, {activation, ctr}}} -> {activation, ctr} end)
          # order by activation and counter
          |> Enum.sort()
          # descending
          |> Enum.reverse()
          # only the highest ctr
          |> Enum.dedup_by(fn {activation, _} -> activation end) do
      BPXE.Engine.Process.Activation.reset_token_generation(activation)
      BPXE.Engine.Process.Activation.set_token_generation(activation, ctr)
    end

    for {{^model_id, id}, {saved_state, _}} <- Set.to_list!(table) do
      # FIXME: infinite timeout is not great, but a short timeout isn't great either, need to figure
      # the best way to handle it
      {_replies, _bad_pids} =
        :syn.multi_call(
          {model, :state_recovery, id},
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
             {from, model, {activation, generation_ctr} = generation, model_id, id} | rest
           ],
           last_commit: last_commit
         } = state
       ) do
    last = last_commit[{model_id, activation}]

    if is_nil(last) or last == generation_ctr - 1 do
      # Again, this is a subsequent generation in model+activation, we can commit it
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
      # But if it is not, we can't
      state
    end
  end
end
