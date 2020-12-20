defmodule BPXE.Service do
  defmodule Request do
    defstruct payload: nil
  end

  defmodule Response do
    defstruct payload: nil
  end

  def start_link(module, options \\ []) do
    GenServer.start_link(module, options)
  end

  def registered(pid, blueprint, name) do
    GenServer.call(pid, {:registered, blueprint, name})
  end

  def call(pid, request, blueprint) do
    GenServer.call(pid, {request, blueprint})
  end

  @callback handle_request(
              request :: %Request{},
              blueprint :: pid(),
              from :: term(),
              state :: term()
            ) ::
              {:reply, term(), term()} | {:noreply, term(), term()}

  @optional_callbacks handle_request: 4

  defmacro __using__(options \\ [state: []]) do
    quote do
      @behaviour BPXE.Service
      use GenServer

      @state [{:options, nil}, {:__monitor__, nil} | unquote(options)[:state] || []]
      defstruct @state

      def init(options) do
        {:ok, %__MODULE__{options: options}}
      end

      def handle_call({:registered, blueprint, _name}, _from, state) do
        monitor = Process.monitor(blueprint)
        {:reply, :ok, %{state | __monitor__: monitor}}
      end

      def handle_call({%BPXE.Service.Request{} = request, blueprint}, from, state) do
        handle_request(request, blueprint, from, state)
      end

      def handle_info({:DOWN, monitor, :process, _, _}, %__MODULE__{__monitor__: monitor} = state) do
        {:stop, :normal, state}
      end

      defoverridable init: 1
    end
  end
end
