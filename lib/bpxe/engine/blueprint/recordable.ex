defmodule BPXE.Engine.Blueprint.Recordable do
  @moduledoc """
  This module allows engine to call either an actual GenServer process
  or its substitute. Mainly designed to achieve calling transparency for
  blueprints and its components.  
  """

  defmacro __using__(options \\ []) do
    quote bind_quoted: [options: options], location: :keep do
      import BPXE.Engine.Blueprint.Recordable, only: [call: 2]
      alias BPXE.Engine.Blueprint.Recordable.Ref

      @recordable_state_key options[:key] || :blueprint
      @recordable_handle options[:handle]

      if is_list(@recordable_handle) do
        # Here we cover a special case in which we need to be able to ID elements by their references
        # Our current assumption is based on the fact that is always the second element of the payload
        #
        defp handle_recordable_call(payload, reference, _from, state) do
          result = %Ref{pid: self(), reference: make_ref(), payload: payload}

          blueprint = Map.get(state, @recordable_state_key, %{})
          blueprint = Map.update(blueprint, reference, [result], fn rest -> [result | rest] end)

          {:reply, {:ok, result}, Map.put(state, @recordable_state_key, blueprint)}
        end

        def handle_call(
              {%Ref{} = reference, :id},
              _from,
              state
            ) do
          blueprint = Map.get(state, @recordable_state_key, %{})

          result =
            Enum.reduce(blueprint, nil, fn {_ref, records}, acc ->
              result =
                Enum.find(records, fn %Ref{payload: payload, reference: ref} ->
                  is_tuple(payload) and ref == reference.reference
                end)

              if result do
                # here's our ID
                elem(result.payload, 1)
              else
                acc
              end
            end)

          {:reply, result, state}
        end

        for call <- @recordable_handle do
          @call call

          def handle_call(
                {%Ref{} = reference, payload},
                from,
                state
              )
              when (is_tuple(payload) and elem(payload, 0) == @call) or payload == @call do
            handle_recordable_call(payload, reference, from, state)
          end

          def handle_call(payload, from, state)
              when (is_tuple(payload) and elem(payload, 0) == @call) or payload == @call do
            handle_recordable_call(payload, nil, from, state)
          end
        end
      end
    end
  end

  defmodule Ref do
    defstruct pid: nil, reference: nil, payload: nil
  end

  def call(server, payload) when is_pid(server) or is_atom(server) do
    GenServer.call(server, payload)
  end

  def call(%Ref{pid: pid} = recordable, payload) do
    GenServer.call(pid, {recordable, payload})
  end
end
