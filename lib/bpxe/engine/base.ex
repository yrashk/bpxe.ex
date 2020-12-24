defmodule BPXE.Engine.Base do
  use BPXE.Engine.Model.Recordable

  defmacro __using__(_ \\ []) do
    quote location: :keep do
      import BPXE.Engine.Base, only: [defstate: 1]
      Module.register_attribute(__MODULE__, :initializer, accumulate: true)
      Module.register_attribute(__MODULE__, :persist_state, accumulate: true)

      @persist_state {BPXE.Engine.Base, :variables}

      def handle_call(:id, _from, state) do
        {:reply, get_state(state, BPXE.Engine.Base).id, state}
      end

      def handle_call(:model, _from, state) do
        {:reply, get_state(state, BPXE.Engine.Base).model, state}
      end

      def handle_call(:module, _from, state) do
        {:reply, __MODULE__, state}
      end

      def handle_call(:add_extension_elements, _from, state) do
        {:reply, {:ok, self()}, state}
      end

      def handle_call({:add_json, nil, json}, _from, state) do
        base_state = get_state(state, BPXE.Engine.Base)

        state =
          put_state(state, BPXE.Engine.Base, %{
            base_state
            | extensions: [{:json, json} | base_state.extensions]
          })

        {:reply, {:ok, nil}, state}
      end

      def initialize(state) do
        Process.put(BPXE.Engine.Base, __MODULE__)

        __initializers__()
        |> Enum.uniq()
        |> Enum.reverse()
        |> Enum.reduce(state, fn initializer, state -> apply(__MODULE__, initializer, [state]) end)
      end

      @initializer :initialize_base

      def initialize_base(state) do
        base_state = get_state(state, BPXE.Engine.Base)

        put_state(
          state,
          BPXE.Engine.Base,
          base_state
          |> Map.put(:variables, %{"id" => base_state.id})
          |> Map.put(:extensions, [])
        )
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

      def handle_call(:variables, _from, state) do
        {:reply, get_state(state, BPXE.Engine.Base).variables, state}
      end

      def handle_call({:merge_variables, variables, token}, _from, state) do
        base_state = get_state(state, BPXE.Engine.Base)

        changes =
          case MapDiff.diff(base_state.variables, variables) do
            %{added: added} -> added |> Map.new()
            _ -> %{}
          end

        variables = Map.merge(base_state.variables, changes)

        if variables != base_state.variables do
          BPXE.Engine.Model.save_state(
            base_state.model,
            token.__generation__,
            base_state.id,
            self(),
            %{
              variables: variables
            }
          )
        end

        state = put_state(state, BPXE.Engine.Base, %{base_state | variables: variables})

        {:reply, :ok, state}
      end

      defp get_state(state, name) do
        state.__layers__[name]
      end

      defp put_state(state, name, value) do
        %{state | __layers__: Map.put(state.__layers__ || %{}, name, value)}
      end

      @before_compile BPXE.Engine.Base
    end
  end

  def id(pid) do
    call(pid, :id)
  end

  def model(pid) do
    GenServer.call(pid, :model)
  end

  def module(pid) do
    GenServer.call(pid, :module)
  end

  def variables(pid) do
    GenServer.call(pid, :variables)
  end

  def merge_variables(pid, variables, token) do
    GenServer.call(pid, {:merge_variables, variables, token})
  end

  def add_extension_elements(pid) do
    call(pid, :add_extension_elements)
  end

  def add_json(pid, json) do
    call(pid, {:add_json, nil, json})
  end

  defmacro __before_compile__(_) do
    quote location: :keep do
      unless Module.defines?(__MODULE__, {:__initializers__, 0}) do
        defp __initializers__(), do: @initializer
      end

      unless Module.defines?(__MODULE__, {:__persisted_state__, 0}) do
        defp __persisted_state__(), do: @persist_state
      end
    end
  end

  defmacro defstate(fields) do
    quote bind_quoted: [fields: fields], location: :keep do
      @state [{:__layers__, %{}} | fields]
      defstruct @state
    end
  end
end
