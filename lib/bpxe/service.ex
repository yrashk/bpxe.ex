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

  defmacro __using__(options \\ [state: []]) do
    quote do
      @behaviour BPXE.Service
      use GenServer

      @state [{:options, nil} | unquote(options)[:state]]
      defstruct @state

      def init(options) do
        {:ok, %__MODULE__{options: options}}
      end

      def handle_call({:registered, blueprint, _name}, _from, state) do
        Process.link(blueprint)
        {:reply, :ok, state}
      end

      def handle_call({%BPXE.Service.Request{} = request, blueprint}, from, state) do
        handle_request(request, blueprint, from, state)
      end

      defoverridable init: 1
    end
  end
end
