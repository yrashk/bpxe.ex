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

        BPXE.Registry.register({BPXE.Engine.Property, attrs["id"]}, attrs)

        {:reply, {:ok, {self(), :property}}, state}
      end

      @initializer :initialize_property_container

      def initialize_property_container(state) do
        put_state(state, BPXE.Engine.PropertyContainer, %{
          properties: %{}
        })
      end

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
end
