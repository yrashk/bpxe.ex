defmodule BPXE.Engine.FlowNode do
  use BPXE.Engine.Blueprint.Recordable

  defmacro __using__(_options \\ []) do
    quote do
      use BPXE.Engine.Base
      use BPXE.Engine.Recoverable
      alias BPXE.Engine.Base
      alias BPXE.Engine.Process.Log

      import BPXE.Engine.FlowNode,
        only: [defstate: 1, defstate: 2]

      def handle_call({:add_incoming, id}, _from, state) do
        :syn.join({state.blueprint.pid, :flow_out, id}, self())
        {:reply, {:ok, id}, %{state | incoming: [id | state.incoming]}}
      end

      def handle_call(:clear_incoming, _from, state) do
        for flow <- state.incoming do
          :syn.leave({state.blueprint.pid, :flow_out, flow}, self())
        end

        {:reply, :ok, %{state | incoming: []}}
      end

      def handle_call({:remove_incoming, id}, _from, state) do
        :syn.leave({state.blueprint.pid, :flow_out, id}, self())
        {:reply, :ok, %{state | incoming: state.incoming -- [id]}}
      end

      def handle_call({:add_outgoing, id}, _from, state) do
        {:reply, {:ok, id}, %{state | outgoing: [id | state.outgoing]}}
      end

      def handle_call({:remove_outgoing, id}, _from, state) do
        {:reply, :ok, %{state | outgoing: state.outgoing -- [id]}}
      end

      def handle_call(:clear_outgoing, _from, state) do
        {:reply, :ok, %{state | outgoing: []}}
      end

      def handle_call({:add_sequence_flow, id, options}, _from, state) do
        :syn.join({state.blueprint.pid, :flow_sequence, id}, self())

        {:reply, {:ok, {BPXE.Engine.FlowNode, {:sequence_flow, self(), id}}},
         %{
           state
           | sequence_flows: Map.put(state.sequence_flows, id, options),
             sequence_flow_order: [id | state.sequence_flow_order]
         }}
      end

      def handle_call({:add_condition_expression, id, options, body}, _from, state) do
        case Map.get(state.sequence_flows, id) do
          nil ->
            {:reply, {:error, :not_found}, state}

          sequence_flow ->
            {:reply, :ok,
             %{
               state
               | sequence_flows:
                   Map.put(
                     state.sequence_flows,
                     id,
                     Map.put(sequence_flow, :conditionExpression, {options, body})
                   )
             }}
        end
      end

      def handle_call(:clear_sequence_flows, _from, state) do
        {:reply, :ok, %{state | sequence_flows: %{}, sequence_flow_order: []}}
      end

      def handle_call({:remove_sequence_flow, id}, _from, state) do
        :syn.leave({state.blueprint.pid, :flow_sequence, id}, self())

        {:reply, Map.get(state.sequence_flows, id),
         %{
           state
           | sequence_flows: Map.delete(state.sequence_flows, id),
             sequence_flow_order: state.sequence_flow_order -- [id]
         }}
      end

      def handle_call(:get_sequence_flows, _from, state) do
        {:reply, state.sequence_flows, state}
      end

      def handle_call(:get_incoming, _from, state) do
        {:reply, state.incoming |> Enum.reverse(), state}
      end

      def handle_call(:get_outgoing, _from, state) do
        {:reply, state.outgoing |> Enum.reverse(), state}
      end

      def handle_call(:synthesize, _from, state) do
        case synthesize(state) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, err} -> {:reply, {:error, err}, state}
        end
      end

      def handle_call(:add_extension_elements, _from, state) do
        {:reply, {:ok, self()}, state}
      end

      def handle_call({:add_json, nil, json}, _from, state) do
        {:reply, {:ok, nil}, %{state | extensions: [{:json, json} | state.extensions]}}
      end

      def handle_info({BPXE.Token.Ack, token_id, id}, state) do
        case Map.get(state.buffer, {token_id, id}) do
          %BPXE.Token{__generation__: generation} ->
            state = %{state | buffer: Map.delete(state.buffer, {token_id, id})}
            save_state(generation, state)
            # if this token has been delivered to all recipients
            unless Enum.any?(state.buffer, fn {{t, _}, _} -> t == token_id end) do
              # commit
              commit_state(generation, state)
            end

            {:noreply, state}

          nil ->
            {:noreply, state}
        end
      end

      def handle_info({%BPXE.Token{__generation__: generation} = token, id}, state) do
        alias BPXE.Engine.Process

        Process.log(state.process, %Log.FlowNodeActivated{
          pid: self(),
          id: state.id,
          token: token,
          token_id: token.token_id
        })

        case handle_token({token, id}, state) do
          {:send, %BPXE.Token{} = new_token, state} ->
            new_token = %{
              new_token
              | __generation__:
                  if(generation == new_token.__generation__,
                    do: next_generation(new_token),
                    else: new_token.__generation__
                  )
            }

            Process.log(state.process, %Log.FlowNodeForward{
              pid: self(),
              id: state.id,
              token_id: token.token_id,
              to: state.outgoing
            })

            sequence_flows =
              state.sequence_flow_order
              |> Enum.reverse()
              # ensure condition-expressioned sequence flows are at the top
              |> Enum.sort_by(fn id -> !state.sequence_flows[id][:conditionExpression] end)

            state =
              Enum.reduce(sequence_flows, state, fn sequence_flow, state ->
                send_token(sequence_flow, new_token, state)
              end)

            save_state(generation, state)
            ack(token, id, state)

            {:noreply, handle_completion(state)}

          {:send, %BPXE.Token{} = new_token, outgoing, state} ->
            new_token = %{
              new_token
              | __generation__:
                  if(generation == new_token.__generation__,
                    do: next_generation(new_token),
                    else: new_token.__generation__
                  )
            }

            Process.log(state.process, %Log.FlowNodeForward{
              pid: self(),
              id: state.id,
              token_id: token.token_id,
              to: outgoing
            })

            state =
              Enum.reduce(outgoing, state, fn sequence_flow, state ->
                send_token(sequence_flow, new_token, state)
              end)

            save_state(generation, state)
            ack(token, id, state)

            {:noreply, handle_completion(state)}

          {:dontsend, state} ->
            save_state(generation, state)
            ack(token, id, state)

            {:noreply, handle_completion(state)}

          {:dontack, state} ->
            {:noreply, handle_completion(state)}
        end
      end

      def handle_token({%BPXE.Token{} = token, _id}, state) do
        {:send, token, state}
      end

      def handle_completion(state) do
        state
      end

      def handle_recovery(recovered, state) do
        state = super(recovered, state)

        Enum.reduce(state.buffer, state, fn {_token_id, sequence_flow}, token ->
          send(sequence_flow, token, state)
        end)
      end

      defp next_generation(%BPXE.Token{} = token) do
        BPXE.Token.next_generation(token)
      end

      defp save_state(generation, state) do
        state_map = Map.from_struct(state)

        saving_state =
          Enum.reduce(persisted_state(), %{}, fn key, acc ->
            Map.put(acc, key, state_map[key])
          end)

        BPXE.Engine.Blueprint.save_state(
          state.blueprint,
          generation,
          state.id,
          self(),
          saving_state
        )
      end

      defp commit_state(generation, state) do
        BPXE.Engine.Blueprint.commit_state(state.blueprint, generation, state.id)
      end

      defp ack(%BPXE.Token{__generation__: 0}, _id, state) do
        commit_state(0, state)
      end

      defp ack(%BPXE.Token{token_id: token_id}, id, state) do
        :syn.publish(
          {state.blueprint.pid, :flow_sequence, id},
          {BPXE.Token.Ack, token_id, id}
        )
      end

      @initializer :init_flow_node

      def init_flow_node(state) do
        :syn.register({state.blueprint.pid, :flow_node, state.id}, self())
        %{state | variables: %{"id" => state.id}}
      end

      def flow_node?() do
        true
      end

      @xsi "http://www.w3.org/2001/XMLSchema-blueprint"
      def send_token(sequence_flow, token, state) do
        alias BPXE.Engine.Process

        proceed =
          case state.sequence_flows[sequence_flow][:conditionExpression] do
            {%{{@xsi, "type"} => formal_expr}, body}
            when formal_expr == "bpmn:tFormalExpression" or formal_expr == "tFormalExpression" ->
              process_vars = Base.variables(state.process)
              {:reply, flow_node_vars, _} = handle_call(:variables, :ignored, state)

              vars = %{
                "process" => process_vars,
                "token" => token.payload,
                "flow_node" => flow_node_vars
              }

              case JMES.search(body, vars) do
                {:ok, result} ->
                  result

                {:error, error} ->
                  Process.log(state.process, %Log.ExpressionErrorOccurred{
                    pid: self(),
                    id: sequence_flow,
                    token_id: token.token_id,
                    expression: body,
                    error: error
                  })

                  false
              end

            _ ->
              true
          end

        if proceed do
          state = send(sequence_flow, token, state)
          %{state | buffer: Map.put(state.buffer, {token.token_id, sequence_flow}, token)}
        else
          state
        end
      end

      def send(sequence_flow, token, state) do
        target = state.sequence_flows[sequence_flow]["targetRef"]

        case :syn.whereis({state.blueprint.pid, :flow_node, target}) do
          pid when is_pid(pid) ->
            send(pid, {token, sequence_flow})

          # FIXME: how should we handle this?
          :undefined ->
            :skip
        end

        state
      end

      def synthesize(state) do
        {:ok, state}
      end

      defoverridable handle_recovery: 2,
                     handle_token: 2,
                     handle_completion: 1,
                     send_token: 3,
                     send: 3,
                     synthesize: 1
    end
  end

  def whereis(blueprint_pid, id) do
    case :syn.whereis({blueprint_pid, :flow_node, id}) do
      :undefined -> nil
      pid when is_pid(pid) -> pid
    end
  end

  def add_outgoing(pid, name) do
    call(pid, {:add_outgoing, name})
  end

  def get_outgoing(pid) do
    call(pid, :get_outgoing)
  end

  def remove_outgoing(pid, name) do
    call(pid, {:remove_outgoing, name})
  end

  def clear_outgoing(pid) do
    call(pid, :clear_outgoing)
  end

  def add_incoming(pid, name) do
    call(pid, {:add_incoming, name})
  end

  def remove_incoming(pid, name) do
    call(pid, {:remove_incoming, name})
  end

  def get_incoming(pid) do
    call(pid, :get_incoming)
  end

  def clear_incoming(pid) do
    call(pid, :clear_incoming)
  end

  def add_sequence_flow(pid, id, options) do
    call(pid, {:add_sequence_flow, id, options})
  end

  def get_sequence_flows(pid) do
    call(pid, :get_sequence_flows)
  end

  def remove_sequence_flow(pid, id) do
    call(pid, {:remove_sequence_flow, id})
  end

  def clear_sequence_flows(pid) do
    call(pid, :clear_sequence_flows)
  end

  def add_condition_expression({:sequence_flow, id, pid}, options, body) do
    call(pid, {:add_condition_expression, id, options, body})
  end

  def add_condition_expression(
        %BPXE.Engine.Blueprint.Recordable.Ref{} = ref,
        options,
        body
      ) do
    call(ref, {:add_condition_expression, options, body})
  end

  def add_extension_elements(pid) do
    call(pid, :add_extension_elements)
  end

  def add_json(pid, json) do
    call(pid, {:add_json, nil, json})
  end

  def synthesize(pid) do
    call(pid, :synthesize)
  end

  def subcall(
        {:sequence_flow, pid, id},
        {:add_condition_expression, options, body}
      ) do
    call(pid, {:add_condition_expression, id, options, body})
  end

  defmacro defstate(struct, options \\ []) do
    struct =
      struct
      |> Map.new()

    persist = Code.eval_quoted(options[:persist]) |> elem(0) || Map.keys(struct)

    persist =
      Enum.reduce(Code.eval_quoted(options[:transient]) |> elem(0) || [], persist, fn key, acc ->
        List.delete(acc, key)
      end)

    struct =
      struct
      |> Map.merge(%{
        incoming: [],
        outgoing: [],
        process: [],
        sequence_flows: Macro.escape(%{}),
        sequence_flow_order: [],
        buffer: Macro.escape(%{}),
        variables: Macro.escape(%{}),
        extensions: []
      })
      |> Map.to_list()

    persist = [:buffer, :variables | persist] |> Enum.uniq()

    quote bind_quoted: [struct: struct, persist: persist] do
      defstruct struct

      defp persisted_state, do: unquote(persist)
    end
  end
end
