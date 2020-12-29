defmodule BPXE.Engine.Recoverable do
  defmacro __using__(_options \\ []) do
    quote location: :keep do
      def handle_info(
            {:syn_multi_call, pid, {BPXE.Engine.Recoverable, :recovered_state, saved_state}},
            state
          ) do
        state = handle_recovery(saved_state, state)
        :syn.multi_call_reply(pid, :ok)
        {:noreply, state}
      end

      defp handle_recovery(saved_state, state) do
        Enum.reduce(__persisted_state__(), state, fn
          {layer, item}, acc ->
            update_in(acc.__layers__[layer], fn m ->
              Map.merge(m || %{}, %{item => saved_state[layer][item]})
            end)

          item, acc ->
            Map.put(acc, item, saved_state[item])
        end)
      end

      defoverridable handle_recovery: 2

      def init_recoverable(state) do
        base_state = get_state(state, BPXE.Engine.Base)
        :syn.join({base_state.model.pid, :state_recovery, base_state.attrs["id"]}, self())
        state
      end

      @initializer :init_recoverable
    end
  end
end
