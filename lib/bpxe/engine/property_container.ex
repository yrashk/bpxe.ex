defmodule BPXE.Engine.PropertyContainer do
  defmacro __using__(_options \\ []) do
    quote location: :keep do
      def handle_call({:add_node, _, "property", attrs}, _from, state) do
        property_container_state = get_state(state, BPXE.Engine.PropertyContainer)

        state =
          put_state(state, BPXE.Engine.PropertyContainer, %{
            property_container_state
            | properties: Map.put(property_container_state.properties, attrs["id"], attrs)
          })

        {:reply, {:ok, {self(), :property}}, state}
      end

      @ext_spec BPXE.BPMN.ext_spec()

      def handle_call({:get_property, id, token}, _from, state) do
        result =
          case state.__layers__[BPXE.Engine.PropertyContainer].properties[id] do
            %{{@ext_spec, "flow"} => "true", "name" => name} ->
              if token do
                {:ok, token.payload[name]}
              else
                {:ok, nil}
              end

            %{"name" => name} ->
              {:ok, state.__layers__[BPXE.Engine.Base].variables[name]}

            nil ->
              {:error, :not_found}
          end

        {:reply, result, state}
      end

      def handle_call({:set_property, id, value, token}, _from, state) do
        {result, state} =
          case state.__layers__[BPXE.Engine.PropertyContainer].properties[id] do
            nil ->
              {{:error, :not_found}, state}

            %{"name" => name} ->
              state = put_in(state.__layers__[BPXE.Engine.Base].variables[name], value)

              if token do
                base_state = get_state(state, BPXE.Engine.Base)

                BPXE.Engine.Model.save_state(
                  base_state.model,
                  token.__generation__,
                  base_state.attrs["id"],
                  self(),
                  %{
                    variables: state.__layers__[BPXE.Engine.Base].variables
                  }
                )
              end

              {:ok, state}
          end

        {:reply, result, state}
      end

      @initializer :initialize_property_container

      def initialize_property_container(state) do
        put_state(state, BPXE.Engine.PropertyContainer, %{
          properties: %{}
        })
      end

      if Module.overridable?(__MODULE__, {:get_input_data, 2}) do
        def get_input_data(id, state) do
          case get_input_data_impl(id, state) do
            {:error, :not_found} ->
              super(id, state)

            {:ok, val} ->
              {:ok, val}
          end
        end
      else
        def get_input_data(id, state) do
          get_input_data_impl(id, state)
        end
      end

      defp get_input_data_impl(id, state) do
        property =
          Enum.find_value(state.__layers__[BPXE.Engine.PropertyContainer].properties, fn {_, prop} ->
            if prop["id"] == id do
              prop
            else
              nil
            end
          end)

        if property do
          base_state = get_state(state, BPXE.Engine.Base)
          {:ok, base_state.variables[property["name"]]}
        else
          {:error, :not_found}
        end
      end

      if Module.overridable?(__MODULE__, {:set_input_data, 4}) do
        def set_input_data(id, value, token, state) do
          case set_input_data_impl_prop(id, value, token, state) do
            {:error, :not_found} ->
              super(id, value, token, state)

            {:ok, state} ->
              {:ok, state}
          end
        end
      else
        def set_input_data(id, value, token, state) do
          set_input_data_impl_prop(id, value, token, state)
        end
      end

      defp set_input_data_impl_prop(id, value, _token, state) do
        property =
          Enum.find_value(state.__layers__[BPXE.Engine.PropertyContainer].properties, fn {_, prop} ->
            if prop["id"] == id do
              prop
            else
              nil
            end
          end)

        if property do
          state = put_in(state.__layers__[BPXE.Engine.Base].variables[property["name"]], value)
          {:ok, state}
        else
          {:error, :not_found}
        end
      end

      defoverridable get_input_data: 2, set_input_data: 4

      if Module.overridable?(__MODULE__, {:get_output_data, 2}) do
        def get_output_data(id, state) do
          # Try to find it in properties, but continue with previous definitions
          # to find it elsewhere
          case get_output_data_impl_prop(id, state) do
            {:error, :not_found} ->
              super(id, state)

            {:ok, val} ->
              {:ok, val}
          end
        end
      else
        def get_output_data(id, state) do
          get_output_data_impl_prop(id, state)
        end
      end

      defp get_output_data_impl_prop(id, state) do
        property =
          Enum.find_value(state.__layers__[BPXE.Engine.PropertyContainer].properties, fn {_, prop} ->
            if prop["id"] == id do
              prop
            else
              nil
            end
          end)

        if property do
          base_state = get_state(state, BPXE.Engine.Base)
          {:ok, base_state.variables[property["name"]]}
        else
          {:error, :not_found}
        end
      end

      # Output association can target ANY item-aware element, so it can be treated same as input data
      # FIXME: this is my reading of the spec. Am I right?

      if Module.overridable?(__MODULE__, {:set_output_data, 4}) do
        def set_output_data(id, value, token, state) do
          case set_output_data_impl(id, value, token, state) do
            {:error, :not_found} ->
              super(id, value, token, state)

            {:ok, state} ->
              {:ok, state}
          end
        end
      else
        def set_output_data(id, value, token, state) do
          set_output_data_impl(id, value, token, state)
        end
      end

      defp set_output_data_impl(id, value, _token, state) do
        property =
          Enum.find_value(state.__layers__[BPXE.Engine.PropertyContainer].properties, fn {_, prop} ->
            if prop["id"] == id do
              prop
            else
              nil
            end
          end)

        if property do
          state = put_in(state.__layers__[BPXE.Engine.Base].variables[property["name"]], value)
          {:ok, state}
        else
          {:error, :not_found}
        end
      end

      defoverridable get_output_data: 2, set_output_data: 4

      # Effectively enables this for FlowNodes only
      if Module.overridable?(__MODULE__, {:send, 3}) do
        @ext_spec BPXE.BPMN.ext_spec()
        def send(sequence_flow, token, state) do
          property_container_state = get_state(state, BPXE.Engine.PropertyContainer)

          token =
            Enum.reduce(property_container_state.properties, token, fn
              {_, %{{@ext_spec, "flow"} => "true", "name" => name}}, acc ->
                update_in(token.payload, fn payload ->
                  Map.update(payload, name, nil, &Function.identity/1)
                end)

              _, acc ->
                acc
            end)

          super(sequence_flow, token, state)
        end
      end
    end
  end

  import BPXE.Engine.BPMN

  def add_property(pid, attrs, body \\ nil) do
    add_node(pid, "property", attrs, body)
  end

  def get_property(pid, id, token \\ nil) do
    GenServer.call(pid, {:get_property, id, token})
  end

  def set_property(pid, id, value, token \\ nil) do
    GenServer.call(pid, {:set_property, id, value, token})
  end
end
