defmodule BPXE.Engine.Activity do
  defmodule StandardLoop do
    defstruct id: nil, attrs: %{}, condition: nil, counter: nil
    use ExConstructor
  end

  defmacro __using__(_options \\ []) do
    quote location: :keep do
      alias BPXE.Engine.Activity.StandardLoop
      alias BPXE.Engine.{Base, Process}
      alias BPXE.Engine.Process.Log
      use BPXE.Engine.PropertyContainer
      use BPXE.Engine.DataInputAssociation
      use BPXE.Engine.DataOutputAssociation

      def handle_call(
            {:add_node, _ref, "standardLoopCharacteristics", %{"id" => id} = attrs},
            _from,
            state
          ) do
        state =
          put_in(
            state.__layers__[BPXE.Engine.Activity].loop,
            StandardLoop.new(id: id, attrs: attrs)
          )

        {:reply, {:ok, {self(), {:standard_loop, id}}}, state}
      end

      def handle_call({:add_node, {:standard_loop, id}, "loopCondition", attrs}, _from, state) do
        state =
          put_in(
            state.__layers__[BPXE.Engine.Activity].loop.condition,
            {id, attrs, nil}
          )

        {:reply, {:ok, {self(), {:standard_loop_condition, id}}}, state}
      end

      def handle_call({:complete_node, {:standard_loop_condition, id}, body}, _from, state) do
        state =
          update_in(
            state.__layers__[BPXE.Engine.Activity].loop.condition,
            fn {id, attrs, _} -> {id, attrs, body} end
          )

        {:reply, :ok, state}
      end

      def handle_token(
            {token, id},
            %{
              __struct__: __MODULE__,
              __layers__: %{BPXE.Engine.Activity => %{loop: %StandardLoop{counter: nil}}}
            } = state
          ) do
        standard_loop(
          token,
          id,
          {:send, token, state},
          put_in(state.__layers__[BPXE.Engine.Activity].loop.counter, 0)
        )
      end

      defp standard_loop(
             token,
             id,
             response,
             state
           ) do
        %StandardLoop{attrs: attrs, counter: ctr} = state.__layers__[BPXE.Engine.Activity].loop

        test_before = (attrs["testBefore"] || "false") == "true"

        loop_maximum =
          if max = attrs["loopMaximum"] do
            {int, _} = Integer.parse(max)
            int
          else
            nil
          end

        if loop_maximum == ctr do
          response
        else
          state = update_in(state.__layers__[BPXE.Engine.Activity].loop.counter, &(&1 + 1))

          if test_before and !test_condition(token, id, state) do
            response
          else
            response =
              handle_token(
                {token, id},
                state
              )

            {token, state} =
              case response do
                {:send, token, _, state} -> {token, state}
                {:send, token, state} -> {token, state}
                {:dontsend, state} -> {token, state}
                {:dontack, state} -> {token, state}
              end

            if test_before or test_condition(token, id, state) do
              standard_loop(token, id, response, state)
            else
              response
            end
          end
        end
      end

      defp test_condition(token, id, state) do
        activity_state = state.__layers__[BPXE.Engine.Activity]

        case activity_state.loop.condition do
          {_, %{{@xsi, "type"} => formal_expr}, body}
          when formal_expr == "bpmn:tFormalExpression" or formal_expr == "tFormalExpression" ->
            base_state = get_state(state, BPXE.Engine.Base)
            process_vars = Base.variables(base_state.process)
            flow_node_vars = get_state(state, BPXE.Engine.Base).variables

            vars = %{
              "process" => process_vars,
              "token" => token.payload,
              "flow_node" => flow_node_vars,
              "loopCounter" => activity_state.loop.counter
            }

            case JMES.search(body, vars) do
              {:ok, result} ->
                result

              {:error, error} ->
                Process.log(base_state.process, %Log.ExpressionErrorOccurred{
                  pid: self(),
                  id: id,
                  token_id: token.token_id,
                  expression: body,
                  error: error
                })

                false
            end

          _ ->
            true
        end
      end

      @initializer :initialize_activity

      def initialize_activity(state) do
        put_state(state, BPXE.Engine.Activity, %{
          loop: nil
        })
      end
    end
  end

  import BPXE.Engine.BPMN

  def add_standard_loop_characteristics(pid, attrs, body \\ nil) do
    add_node(pid, "standardLoopCharacteristics", attrs, body)
  end

  def add_loop_condition(pid, attrs, body \\ nil) do
    add_node(pid, "loopCondition", attrs, body)
  end
end
