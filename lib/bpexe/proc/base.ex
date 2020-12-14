defmodule BPEXE.Proc.Base do
  defmacro __using__(_ \\ []) do
    quote do
      def handle_call(:id, _from, state) do
        {:reply, state.id, state}
      end
    end
  end

  def id(pid) do
    GenServer.call(pid, :id)
  end
end
