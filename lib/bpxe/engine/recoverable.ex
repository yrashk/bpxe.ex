defmodule BPXE.Engine.Recoverable do
  defmacro __using__(_options \\ []) do
    quote do
      def handle_info(
            {:syn_multi_call, pid, {BPXE.Engine.Recoverable, :recovered_state, saved_state}},
            state
          ) do
        state = handle_recovery(saved_state, state)
        :syn.multi_call_reply(pid, :ok)
        {:noreply, state}
      end

      defp handle_recovery(saved_state, state) do
        saved_keys = Map.keys(saved_state)
        keys = Map.keys(state)
        unknown_keys = saved_keys -- keys

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

      def init_recoverable(state) do
        :syn.join({state.blueprint.pid, :state_recovery, state.id}, self())
        state
      end

      @initializer :init_recoverable
    end
  end
end
