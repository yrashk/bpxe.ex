defmodule BPXE.Engine.Base do
  defmacro __using__(_ \\ []) do
    quote do
      Module.register_attribute(__MODULE__, :initializer, accumulate: true)

      def handle_call(:id, _from, state) do
        {:reply, state.id, state}
      end

      def handle_call(:module, _from, state) do
        {:reply, __MODULE__, state}
      end

      def initialize(state) do
        Process.put(BPXE.Engine.Base, __MODULE__)

        __initializers__()
        |> Enum.uniq()
        |> Enum.reduce(state, fn initializer, state -> apply(__MODULE__, initializer, [state]) end)
      end

      defp start_link(args) do
        :proc_lib.start_link(__MODULE__, :init, args)
      end

      defp init_ack() do
        :proc_lib.init_ack({:ok, self()})
      end

      def enter_loop(state) do
        :gen_server.enter_loop(__MODULE__, [], state)
      end

      @before_compile BPXE.Engine.Base
    end
  end

  def id(pid) do
    GenServer.call(pid, :id)
  end

  def module(pid) do
    GenServer.call(pid, :module)
  end

  defmacro __before_compile__(_) do
    quote location: :keep do
      defp __initializers__, do: @initializer || []
    end
  end
end
