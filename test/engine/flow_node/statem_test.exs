defmodule BPXETest.Engine.FlowNode.StateM do
  use PropCheck.StateM.ModelDSL
  use PropCheck
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  defmodule TestFlowNode do
    use BPXE.Engine.FlowNode

    defstate master: nil

    def start_link(element, attrs, model, process) do
      start_link([{element, attrs, model, process}])
    end

    def init({_element, attrs, model, process}) do
      state =
        %__MODULE__{master: attrs[:master]}
        |> put_state(BPXE.Engine.Base, %{attrs: attrs, model: model, process: process})
        |> initialize()

      init_ack()
      enter_loop(state)
    end
  end

  property "bare flow node operates correctly" do
    forall cmds in commands(__MODULE__) do
      trap_exit do
        alias BPXE.Engine.Model

        # Setup model & process
        {:ok, model} = Model.start_link()
        {:ok, _} = Model.add_process(model, %{"id" => "process"})
        {:ok, process} = Model.provision_process(model, "process")

        # Configure the process instance manually
        {:ok, pid} =
          BPXE.Engine.BPMN.add_node(
            process,
            "flowNode",
            %{module: TestFlowNode, master: self()},
            nil
          )

        Process.register(pid, __MODULE__)

        r = run_commands(__MODULE__, cmds)

        Process.exit(pid, :kill)

        {_history, _state, result} = r

        (result == :ok)
        |> when_fail(print_report(r, cmds))
      end
    end
  end

  alias BPXE.Engine.FlowNode

  defp id(), do: integer()

  defstruct incoming: [], outgoing: []

  def initial_state() do
    %__MODULE__{}
  end

  def command_gen(state) do
    cmds = [
      {:add_incoming, [id()]},
      {:get_incoming, []},
      {:clear_incoming, []},
      {:add_outgoing, [id()]},
      {:get_outgoing, []},
      {:clear_outgoing, []}
    ]

    cmds =
      if length(state.incoming) > 0 do
        [{:remove_incoming, [oneof(state.incoming)]} | cmds]
      else
        cmds
      end

    cmds =
      if length(state.outgoing) > 0 do
        [{:remove_outgoing, [oneof(state.outgoing)]} | cmds]
      else
        cmds
      end

    oneof(cmds)
  end

  defcommand :add_incoming do
    def impl(id), do: FlowNode.add_incoming(__MODULE__, %{}, id)

    def next(state, [id], _) do
      # Ensure if a duplicate incoming addition is requested,
      # it's not actually added to the list. The original one is kept
      if Enum.find(state.incoming, fn x -> x == id end) do
        state
      else
        %{state | incoming: [id | state.incoming]}
      end
    end
  end

  defcommand :remove_incoming do
    def impl(id), do: FlowNode.remove_incoming(__MODULE__, id)

    def next(state, [id], _) do
      %{state | incoming: state.incoming -- [id]}
    end
  end

  defcommand :clear_incoming do
    def impl(), do: FlowNode.clear_incoming(__MODULE__)

    def next(state, [], _) do
      %{state | incoming: []}
    end
  end

  defcommand :get_incoming do
    def impl(), do: FlowNode.get_incoming(__MODULE__)

    def post(state, [], result) do
      result == state.incoming |> Enum.reverse()
    end
  end

  defcommand :add_outgoing do
    def impl(id), do: FlowNode.add_outgoing(__MODULE__, %{}, id)

    def next(state, [id], _) do
      # Ensure if a duplicate outgoing addition is requested,
      # it's not actually added to the list. The original one is kept
      if Enum.find(state.outgoing, fn x -> x == id end) do
        state
      else
        %{state | outgoing: [id | state.outgoing]}
      end
    end
  end

  defcommand :remove_outgoing do
    def impl(id), do: FlowNode.remove_outgoing(__MODULE__, id)

    def next(state, [id], _) do
      %{state | outgoing: state.outgoing -- [id]}
    end
  end

  defcommand :clear_outgoing do
    def impl(), do: FlowNode.clear_outgoing(__MODULE__)

    def next(state, [], _) do
      %{state | outgoing: []}
    end
  end

  defcommand :get_outgoing do
    def impl(), do: FlowNode.get_outgoing(__MODULE__)

    def post(state, [], result) do
      result == state.outgoing |> Enum.reverse()
    end
  end
end
