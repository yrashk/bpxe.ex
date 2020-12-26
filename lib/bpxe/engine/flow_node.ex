defmodule BPXE.Engine.FlowNode do
  use BPXE.Engine.Model.Recordable

  defmacro __using__(_options \\ []) do
    quote location: :keep do
      use BPXE.Engine.Base
      use BPXE.Engine.Recoverable
      alias BPXE.Engine.{Base, FlowNode}
      alias BPXE.Engine.Process.Log

      Module.register_attribute(__MODULE__, :persist_state, accumulate: true)

      @persist_state {BPXE.Engine.FlowNode, :buffer}

      def handle_call({:add_incoming, id}, _from, state) do
        :syn.join({get_state(state, BPXE.Engine.Base).model.pid, :flow_out, id}, self())
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        state =
          if Enum.find(flow_node_state.incoming, &(&1 == id)) do
            state
          else
            put_state(state, BPXE.Engine.FlowNode, %{
              flow_node_state
              | incoming: [id | flow_node_state.incoming]
            })
          end

        {:reply, {:ok, id}, state}
      end

      def handle_call(:clear_incoming, _from, state) do
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)
        base_state = get_state(state, BPXE.Engine.Base)

        for flow <- flow_node_state.incoming do
          :syn.leave({base_state.model.pid, :flow_out, flow}, self())
        end

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | incoming: []
          })

        {:reply, :ok, state}
      end

      def handle_call({:remove_incoming, id}, _from, state) do
        :syn.leave({get_state(state, BPXE.Engine.Base).model.pid, :flow_out, id}, self())
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | incoming: flow_node_state.incoming -- [id]
          })

        {:reply, :ok, state}
      end

      def handle_call({:add_outgoing, id}, _from, state) do
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        state =
          if Enum.find(flow_node_state.outgoing, &(&1 == id)) do
            state
          else
            state =
              put_state(state, BPXE.Engine.FlowNode, %{
                flow_node_state
                | outgoing: [id | flow_node_state.outgoing]
              })
          end

        {:reply, {:ok, id}, state}
      end

      def handle_call({:remove_outgoing, id}, _from, state) do
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | outgoing: flow_node_state.outgoing -- [id]
          })

        {:reply, :ok, state}
      end

      def handle_call(:clear_outgoing, _from, state) do
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | outgoing: []
          })

        {:reply, :ok, state}
      end

      def handle_call({:add_sequence_flow, id, attrs}, _from, state) do
        :syn.join({get_state(state, BPXE.Engine.Base).model.pid, :flow_sequence, id}, self())

        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | sequence_flows: Map.put(flow_node_state.sequence_flows, id, attrs),
              sequence_flow_order: [id | flow_node_state.sequence_flow_order]
          })

        {:reply, {:ok, {FlowNode, {:sequence_flow, self(), id}}}, state}
      end

      def handle_call({:add_condition_expression, id, attrs, body}, _from, state) do
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        case Map.get(flow_node_state.sequence_flows, id) do
          nil ->
            {:reply, {:error, :not_found}, state}

          sequence_flow ->
            state =
              put_state(state, BPXE.Engine.FlowNode, %{
                flow_node_state
                | sequence_flows:
                    Map.put(
                      flow_node_state.sequence_flows,
                      id,
                      Map.put(sequence_flow, :conditionExpression, {attrs, body})
                    )
              })

            {:reply, :ok, state}
        end
      end

      def handle_call(:clear_sequence_flows, _from, state) do
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | sequence_flows: %{},
              sequence_flow_order: []
          })

        {:reply, :ok, state}
      end

      def handle_call({:remove_sequence_flow, id}, _from, state) do
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)
        :syn.leave({get_state(state, BPXE.Engine.Base).model.pid, :flow_sequence, id}, self())

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | sequence_flows: Map.delete(flow_node_state.sequence_flows, id),
              sequence_flow_order: flow_node_state.sequence_flow_order -- [id]
          })

        {:reply, Map.get(flow_node_state.sequence_flows, id), state}
      end

      def handle_call(:get_sequence_flows, _from, state) do
        {:reply, get_state(state, BPXE.Engine.FlowNode).sequence_flows, state}
      end

      def handle_call(:get_incoming, _from, state) do
        {:reply, get_state(state, BPXE.Engine.FlowNode).incoming |> Enum.reverse(), state}
      end

      def handle_call(:get_outgoing, _from, state) do
        {:reply, get_state(state, BPXE.Engine.FlowNode).outgoing |> Enum.reverse(), state}
      end

      def handle_call(:synthesize, _from, state) do
        case synthesize(state) do
          {:ok, state} -> {:reply, :ok, state}
          {:error, err} -> {:reply, {:error, err}, state}
        end
      end

      def handle_info({BPXE.Token.Ack, token_id, id}, state) do
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        case Map.get(flow_node_state.buffer, {token_id, id}) do
          %BPXE.Token{__generation__: generation} ->
            flow_node_state = %{
              flow_node_state
              | buffer: Map.delete(flow_node_state.buffer, {token_id, id})
            }

            state = put_state(state, BPXE.Engine.FlowNode, flow_node_state)

            save_state(generation, state)
            # if this token has been delivered to all recipients
            unless Enum.any?(flow_node_state.buffer, fn {{t, _}, _} -> t == token_id end) do
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

        base_state = get_state(state, BPXE.Engine.Base)
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        Process.log(base_state.process, %Log.FlowNodeActivated{
          pid: self(),
          id: base_state.id,
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

            base_state = get_state(state, BPXE.Engine.Base)

            Process.log(base_state.process, %Log.FlowNodeForward{
              pid: self(),
              id: base_state.id,
              token_id: token.token_id,
              to: flow_node_state.outgoing
            })

            sequence_flows =
              flow_node_state.sequence_flow_order
              |> Enum.reverse()
              # ensure condition-expressioned sequence flows are at the top
              |> Enum.sort_by(fn id ->
                !flow_node_state.sequence_flows[id][:conditionExpression]
              end)

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

            base_state = get_state(state, BPXE.Engine.Base)

            Process.log(base_state.process, %Log.FlowNodeForward{
              pid: self(),
              id: base_state.id,
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
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        Enum.reduce(flow_node_state.buffer, state, fn {_token_id, sequence_flow}, token ->
          send(sequence_flow, token, state)
        end)
      end

      defp next_generation(%BPXE.Token{} = token) do
        BPXE.Token.next_generation(token)
      end

      defp save_state(generation, state) do
        state_map = Map.from_struct(state)

        saving_state =
          Enum.reduce(__persisted_state__(), %{}, fn
            {layer, key}, acc ->
              Map.update(acc, layer, %{key => state_map[:__layers__][layer][key]}, fn map ->
                Map.put(map, key, state_map[:__layers__][layer][key])
              end)

            key, acc ->
              Map.put(acc, key, state_map[key])
          end)

        base_state = get_state(state, BPXE.Engine.Base)

        BPXE.Engine.Model.save_state(
          base_state.model,
          generation,
          base_state.id,
          self(),
          saving_state
        )
      end

      defp commit_state(generation, state) do
        base_state = get_state(state, BPXE.Engine.Base)
        BPXE.Engine.Model.commit_state(base_state.model, generation, base_state.id)
      end

      defp ack(%BPXE.Token{__generation__: 0}, _id, state) do
        commit_state(0, state)
      end

      defp ack(%BPXE.Token{token_id: token_id}, id, state) do
        base_state = get_state(state, BPXE.Engine.Base)

        :syn.publish(
          {base_state.model.pid, :flow_sequence, id},
          {BPXE.Token.Ack, token_id, id}
        )
      end

      @initializer :init_flow_node

      def init_flow_node(state) do
        base_state = get_state(state, BPXE.Engine.Base)
        :syn.register({base_state.model.pid, :flow_node, base_state.id}, self())

        layer = %{
          incoming: [],
          outgoing: [],
          sequence_flows: %{},
          sequence_flow_order: [],
          buffer: %{}
        }

        put_state(state, BPXE.Engine.FlowNode, layer)
      end

      @xsi "http://www.w3.org/2001/XMLSchema-instance"
      def send_token(sequence_flow, token, state) do
        alias BPXE.Engine.Process

        base_state = get_state(state, BPXE.Engine.Base)
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        proceed =
          case flow_node_state.sequence_flows[sequence_flow][:conditionExpression] do
            {%{{@xsi, "type"} => formal_expr}, body}
            when formal_expr == "bpmn:tFormalExpression" or formal_expr == "tFormalExpression" ->
              process_vars = Base.variables(base_state.process)
              flow_node_vars = get_state(state, BPXE.Engine.Base).variables

              vars = %{
                "process" => process_vars,
                "flow" => token.payload,
                "flow_node" => flow_node_vars
              }

              case JMES.search(body, vars) do
                {:ok, result} ->
                  result

                {:error, error} ->
                  Process.log(base_state.process, %Log.ExpressionErrorOccurred{
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

          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | buffer: Map.put(flow_node_state.buffer, {token.token_id, sequence_flow}, token)
          })
        else
          state
        end
      end

      def send(sequence_flow, token, state) do
        base_state = get_state(state, BPXE.Engine.Base)
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        target = flow_node_state.sequence_flows[sequence_flow]["targetRef"]

        case :syn.whereis({base_state.model.pid, :flow_node, target}) do
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

  def whereis(model_pid, id) do
    case :syn.whereis({model_pid, :flow_node, id}) do
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

  def add_sequence_flow(pid, id, attrs) do
    call(pid, {:add_sequence_flow, id, attrs})
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

  def add_condition_expression({:sequence_flow, id, pid}, attrs, body) do
    call(pid, {:add_condition_expression, id, attrs, body})
  end

  def add_condition_expression(
        %BPXE.Engine.Model.Recordable.Ref{} = ref,
        attrs,
        body
      ) do
    call(ref, {:add_condition_expression, attrs, body})
  end

  def synthesize(pid) do
    call(pid, :synthesize)
  end

  def subcall(
        {:sequence_flow, pid, id},
        {:add_condition_expression, attrs, body}
      ) do
    call(pid, {:add_condition_expression, id, attrs, body})
  end
end
