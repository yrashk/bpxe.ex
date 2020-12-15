defmodule BPEXE.Proc.Recoverable do
  defmacro __using__(_options \\ []) do
    quote do
      import BPEXE.Proc.Recoverable, only: [init_recoverable: 1]

      def handle_info(
            {:syn_multi_call, pid, {BPEXE.Proc.Recoverable, :recovered_state, saved_state}},
            state
          ) do
        state = handle_recovery(saved_state, state)
        :syn.multi_call_reply(pid, :ok)
        {:noreply, state}
      end

      defp handle_recovery(saved_state, state) do
        saved_keys = Map.keys(saved_state)
        keys = Map.keys(state)
        unknown_keys = keys -- saved_keys
        keys = keys -- unknown_keys

        state =
          Enum.reduce(unknown_keys, state, fn k, acc ->
            case handle_unknown_state_key(k, saved_state[k]) do
              :skip -> acc
              {k1, v1} -> Map.put(acc, k1, 1)
            end
          end)

        saved_state =
          Enum.reduce(unknown_keys, saved_state, fn k, acc ->
            Map.delete(acc, k)
          end)

        Map.merge(state, saved_state)
      end

      defp handle_unknown_state_key(_key, _value) do
        :skip
      end

      defoverridable handle_recovery: 2, handle_unknown_state_key: 2
    end
  end

  def init_recoverable(state) do
    :syn.join({state.instance.pid, :state_recovery, state.id}, self())
  end
end
