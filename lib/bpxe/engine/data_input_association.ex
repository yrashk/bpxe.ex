defmodule BPXE.Engine.DataInputAssociation do
  defmacro __using__(_options \\ []) do
    quote location: :keep do
      def handle_call({:add_node, _ref, "dataInputAssociation", attrs}, _from, state) do
        state =
          put_in(state.__layers__[BPXE.Engine.DataInputAssociation].associations[attrs["id"]], %{
            source: nil,
            target: nil
          })

        {:reply, {:ok, {self(), {:dataInputAssociation, attrs["id"]}}}, state}
      end

      def handle_call({:add_node, {:dataInputAssociation, id}, "sourceRef", _attrs}, _from, state) do
        {:reply, {:ok, {self(), {:dataInputAssociationSource, id}}}, state}
      end

      def handle_call({:complete_node, {:dataInputAssociationSource, id}, body}, _from, state) do
        state =
          put_in(
            state.__layers__[BPXE.Engine.DataInputAssociation].associations[id][:source],
            body
          )

        {:reply, {:ok, {self(), {:dataInputAssociationSource, id}}}, state}
      end

      def handle_call({:add_node, {:dataInputAssociation, id}, "targetRef", _attrs}, _from, state) do
        {:reply, {:ok, {self(), {:dataInputAssociationTarget, id}}}, state}
      end

      def handle_call({:complete_node, {:dataInputAssociationTarget, id}, body}, _from, state) do
        state =
          put_in(
            state.__layers__[BPXE.Engine.DataInputAssociation].associations[id][:target],
            body
          )

        {:reply, {:ok, {self(), {:dataInputAssociationTarget, id}}}, state}
      end

      @initializer :initialize_data_input_association

      def initialize_data_input_association(state) do
        put_state(state, BPXE.Engine.DataInputAssociation, %{
          associations: %{}
        })
      end

      def before_handle_token({token, id}, state) do
        input_assoc_state = state.__layers__[BPXE.Engine.DataInputAssociation].associations

        Enum.reduce(input_assoc_state, {:ok, state}, fn
          {_, data_state}, {:ok, state} ->
            source = data_state[:source]
            target = data_state[:target]

            if !!source and !!target do
              get_input_data(source, state)
              |> Result.map_error(fn
                :not_found ->
                  {:source_ref_not_found, source}

                err ->
                  err
              end)
              |> Result.and_then(fn data ->
                set_input_data(target, data, token, state)
              end)
              |> Result.map_error(fn
                :not_found ->
                  {:target_ref_not_found, target}

                err ->
                  err
              end)
            else
              {:ok, state}
            end

          _, {:error, err} ->
            {:error, err}
        end)
        |> Result.and_then(fn state ->
          super({token, id}, state)
        end)
      end

      defoverridable before_handle_token: 2

      @before_compile BPXE.Engine.DataInputAssociation
    end
  end

  import BPXE.Engine.BPMN

  def add(pid, options) do
    add_node(pid, "dataInputAssociation")
    |> Result.and_then(fn ia ->
      [
        add_node(ia, "sourceRef", options[:source]),
        add_node(ia, "targetRef", options[:target])
        # TODO: handle transformation
        # TODO: handle the ability to specify multiple sources w/ transformation
        # TODO: handle assignment
      ]
      |> Result.fold()
      |> Result.map(fn _ -> ia end)
    end)
  end

  defmacro __before_compile__(_) do
    quote do
      unless (Module.defines?(__MODULE__, {:get_input_data, 2}) and
                Module.defines?(__MODULE__, {:set_input_data, 4})) or
               (Module.overridable?(__MODULE__, {:get_input_data, 2}) and
                  Module.overridable?(__MODULE__, {:set_input_data, 4})) do
        raise "#{__MODULE__} must define `get_input_data/2` and `set_input_data/4`"
      end
    end
  end
end
