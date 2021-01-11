defmodule BPXE.Engine.InputOutput do
  defmacro __using__(_options \\ []) do
    quote do
      def handle_call({:add_node, _ref, "ioSpecification", _attrs}, _from, state) do
        {:reply, {:ok, {self(), :ioSpecification}}, state}
      end

      def handle_call({:add_node, :ioSpecification, "dataInput", attrs}, _from, state) do
        state =
          put_in(
            state.__layers__[BPXE.Engine.InputOutput].inputs[attrs["id"]],
            BPXE.Engine.DataInput.new(attrs: attrs)
          )

        {:reply, {:ok, {self(), {:dataInput, attrs["id"]}}}, state}
      end

      def handle_call({:add_node, {:dataInput, id}, "dataState", attrs}, _from, state) do
        state =
          update_in(
            state.__layers__[BPXE.Engine.InputOutput].inputs[id],
            fn input ->
              %{input | state: attrs["name"]}
            end
          )

        {:reply, {:ok, {self(), {:dataInputState, id}}}, state}
      end

      def handle_call({:add_node, _ref, "inputSet", attrs}, _from, state) do
        state =
          put_in(
            state.__layers__[BPXE.Engine.InputOutput].input_sets[attrs["id"]],
            BPXE.Engine.InputSet.new(attrs: attrs)
          )

        {:reply, {:ok, {self(), {:inputSet, attrs["id"]}}}, state}
      end

      for ref <- ~w(dataInputRefs optionalInputRefs whileExecutingInputRefs outputSetRefs) do
        @element ref
        @field ProperCase.snake_case(@element) |> String.to_atom()

        def handle_call({:add_node, {:inputSet, id}, @element, _attrs}, _from, state) do
          {:reply, {:ok, {self(), {:inputSet, @element, id}}}, state}
        end

        def handle_call({:complete_node, {:inputSet, @element, id}, ref}, _from, state) do
          state =
            update_in(
              state.__layers__[BPXE.Engine.InputOutput].input_sets[id],
              fn input_set ->
                Map.update(input_set, @field, [ref], &[ref | &1])
              end
            )

          {:reply, {:ok, {self(), {:inputSet, @element, id}}}, state}
        end
      end

      def handle_call({:add_node, :ioSpecification, "dataOutput", attrs}, _from, state) do
        state =
          put_in(
            state.__layers__[BPXE.Engine.InputOutput].outputs[attrs["id"]],
            BPXE.Engine.DataOutput.new(attrs: attrs)
          )

        {:reply, {:ok, {self(), {:dataOutput, attrs["id"]}}}, state}
      end

      def handle_call({:add_node, {:dataOutput, id}, "dataState", attrs}, _from, state) do
        state =
          update_in(
            state.__layers__[BPXE.Engine.InputOutput].outputs[id],
            fn output ->
              %{output | state: attrs["name"]}
            end
          )

        {:reply, {:ok, {self(), {:dataOutputState, id}}}, state}
      end

      def handle_call({:add_node, _ref, "outputSet", attrs}, _from, state) do
        state =
          put_in(
            state.__layers__[BPXE.Engine.InputOutput].output_sets[attrs["id"]],
            BPXE.Engine.OutputSet.new(attrs: attrs)
          )

        {:reply, {:ok, {self(), {:outputSet, attrs["id"]}}}, state}
      end

      for ref <- ~w(dataOutputRefs optionalOutputRefs whileExecutingOutputRefs inputSetRefs) do
        @element ref
        @field ProperCase.snake_case(@element) |> String.to_atom()

        def handle_call({:add_node, {:outputSet, id}, @element, _attrs}, _from, state) do
          {:reply, {:ok, {self(), {:outputSet, @element, id}}}, state}
        end

        def handle_call({:complete_node, {:outputSet, @element, id}, ref}, _from, state) do
          state =
            update_in(
              state.__layers__[BPXE.Engine.InputOutput].output_sets[id],
              fn output_set ->
                Map.update(output_set, @field, [ref], &[ref | &1])
              end
            )

          {:reply, {:ok, {self(), {:outputSet, @element, id}}}, state}
        end
      end

      @initializer :initialize_input_output

      def initialize_input_output(state) do
        put_state(state, BPXE.Engine.InputOutput, %{
          inputs: %{},
          input_sets: %{},
          input_values: %{},
          outputs: %{},
          output_sets: %{},
          output_values: %{}
        })
      end

      if Module.overridable?(__MODULE__, {:set_input_data, 4}) do
        def set_input_data(id, value, token, state) do
          case set_input_data_impl_io(id, value, token, state) do
            {:error, :not_found} ->
              super(id, value, token, state)

            {:ok, state} ->
              {:ok, state}
          end
        end
      else
        def set_input_data(id, value, token, state) do
          set_input_data_impl_io(id, value, token, state)
        end
      end

      defp set_input_data_impl_io(id, value, token, state) do
        if Map.has_key?(state.__layers__[BPXE.Engine.InputOutput].inputs, id) do
          state = put_in(state.__layers__[BPXE.Engine.InputOutput].input_values[id], value)
          {:ok, state}
        else
          {:error, :not_found}
        end
      end

      defoverridable set_input_data: 4

      if Module.overridable?(__MODULE__, {:get_output_data, 2}) do
        def get_output_data(id, state) do
          case get_output_data_impl_io(id, state) do
            {:error, :not_found} ->
              super(id, state)

            {:ok, val} ->
              {:ok, val}
          end
        end
      else
        def get_output_data(id, state) do
          get_output_data_impl_io(id, state)
        end
      end

      defp get_output_data_impl_io(id, state) do
        if Map.has_key?(state.__layers__[BPXE.Engine.InputOutput].outputs, id) do
          {:ok, state.__layers__[BPXE.Engine.InputOutput].output_values[id]}
        else
          {:error, :not_found}
        end
      end

      defoverridable get_output_data: 2

      defp get_input_set(state, id \\ nil) do
        input_sets = state.__layers__[BPXE.Engine.InputOutput].input_sets
        id = id || Map.keys(input_sets) |> List.first()

        case input_sets[id] do
          nil ->
            nil

          %BPXE.Engine.InputSet{data_input_refs: refs} ->
            input_values = state.__layers__[BPXE.Engine.InputOutput].input_values
            refs |> Enum.reverse() |> Enum.map(&input_values[&1])
        end
      end

      def set_output_set(values, token, state, id \\ nil) do
        output_sets = state.__layers__[BPXE.Engine.InputOutput].output_sets
        id = id || Map.keys(output_sets) |> List.first()

        case output_sets[id] do
          nil ->
            {:ok, state}

          %BPXE.Engine.OutputSet{data_output_refs: refs} ->
            state =
              Enum.reduce(refs |> Enum.reverse() |> Enum.zip(values), state, fn {ref, val}, acc ->
                put_in(acc.__layers__[BPXE.Engine.InputOutput].output_values[ref], val)
              end)

            {:ok, state}
        end
      end
    end
  end

  import BPXE.Engine.BPMN

  def add_io_specification(node) do
    add_node(node, "ioSpecification")
  end

  def add_data_input(node, attrs \\ %{}) do
    add_node(node, "dataInput", attrs)
  end

  def add_data_output(node, attrs \\ %{}) do
    add_node(node, "dataOutput", attrs)
  end

  def add_data_state(node, state) do
    add_node(node, "dataState", name: state)
  end

  def add_input_set(node, attrs \\ %{}) do
    add_node(node, "inputSet", attrs)
  end

  def add_data_input_ref(node, ref) do
    add_node(node, "dataInputRefs", ref)
  end

  def add_optional_input_ref(node, ref) do
    add_node(node, "optionalInputRefs", ref)
  end

  def add_while_executing_input_ref(node, ref) do
    add_node(node, "whileExecutingInputRefs", ref)
  end

  def add_output_set_ref(node, ref) do
    add_node(node, "outputSetRefs", ref)
  end

  def add_output_set(node, attrs \\ %{}) do
    add_node(node, "outputSet", attrs)
  end

  def add_data_output_ref(node, ref) do
    add_node(node, "dataOutputRefs", ref)
  end

  def add_optional_output_ref(node, ref) do
    add_node(node, "optionalOutputRefs", ref)
  end

  def add_while_executing_output_ref(node, ref) do
    add_node(node, "whileExecutingOutputRefs", ref)
  end

  def add_input_set_ref(node, ref) do
    add_node(node, "inputSetRefs", ref)
  end
end
