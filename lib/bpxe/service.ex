defmodule BPXE.Service do
  defmodule Request do
    defstruct payload: nil
  end

  defmodule Response do
    defstruct payload: nil
  end

  @default_timeout 5000

  def default_timeout(), do: @default_timeout

  def start_link(module, options \\ []) do
    GenServer.start_link(module, options)
  end

  def registered(pid, model, name) do
    GenServer.call(pid, {:registered, model, name})
  end

  def call(pid, request, model, timeout \\ nil) do
    GenServer.call(pid, {request, model}, timeout || default_timeout())
  end

  @callback handle_request(
              request :: %Request{},
              model :: pid(),
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

      def handle_call({:registered, model, _name}, _from, state) do
        monitor = Process.monitor(model)
        {:reply, :ok, %{state | __monitor__: monitor}}
      end

      def handle_call({%BPXE.Service.Request{} = request, model}, from, state) do
        handle_request(request, model, from, state)
      end

      def handle_info({:DOWN, monitor, :process, _, _}, %__MODULE__{__monitor__: monitor} = state) do
        {:stop, :normal, state}
      end

      def handle_request(_request, _model, _from, state) do
        {:reply, %BPXE.Service.Response{}, state}
      end

      defoverridable init: 1, handle_request: 4
    end
  end
end
