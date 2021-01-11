defmodule BPXE.Engine.FlowNode do
  defmacro __using__(_options \\ []) do
    quote location: :keep do
      use BPXE.Engine.Base
      use BPXE.Engine.Recoverable
      alias BPXE.Engine.{Base, FlowNode}
      alias BPXE.Engine.Process.Log

      Module.register_attribute(__MODULE__, :persist_state, accumulate: true)

      @persist_state {BPXE.Engine.FlowNode, :buffer}

      def handle_call({:add_node, _, "incoming", _attrs}, _from, state) do
        {:reply, {:ok, {self(), :incoming}}, state}
      end

      def handle_call({:complete_node, :incoming, id}, _from, state) do
        BPXE.Channel.join({get_state(state, BPXE.Engine.Base).model.pid, :flow_out, id})
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
          BPXE.Channel.leave({base_state.model.pid, :flow_out, flow})
        end

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | incoming: []
          })

        {:reply, :ok, state}
      end

      def handle_call({:remove_incoming, id}, _from, state) do
        BPXE.Channel.leave({get_state(state, BPXE.Engine.Base).model.pid, :flow_out, id})
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | incoming: flow_node_state.incoming -- [id]
          })

        {:reply, :ok, state}
      end

      def handle_call({:add_node, _, "outgoing", _attrs}, _from, state) do
        {:reply, {:ok, {self(), :outgoing}}, state}
      end

      def handle_call({:complete_node, :outgoing, id}, _from, state) do
        BPXE.Channel.join({get_state(state, BPXE.Engine.Base).model.pid, :flow_sequence, id})
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
        BPXE.Channel.leave({get_state(state, BPXE.Engine.Base).model.pid, :flow_sequence, id})
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

        for outgoing <- flow_node_state.outgoing do
          BPXE.Channel.leave(
            {get_state(state, BPXE.Engine.Base).model.pid, :flow_sequence, outgoing}
          )
        end

        state =
          put_state(state, BPXE.Engine.FlowNode, %{
            flow_node_state
            | outgoing: []
          })

        {:reply, :ok, state}
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
          id: base_state.attrs["id"],
          token: token,
          token_id: token.token_id
        })

        case before_handle_token({token, id}, state) do
          {:ok, state} ->
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
                  id: base_state.attrs["id"],
                  token_id: token.token_id,
                  to: flow_node_state.outgoing
                })

                process_sequence_flows = sequence_flows(state)

                sequence_flows =
                  flow_node_state.outgoing
                  |> Enum.reverse()
                  # ensure condition-expressioned sequence flows are at the top
                  |> Enum.sort_by(fn id ->
                    !process_sequence_flows[id][:conditionExpression]
                  end)
                  |> Enum.map(&process_sequence_flows[&1])

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
                  id: base_state.attrs["id"],
                  token_id: token.token_id,
                  to: outgoing
                })

                process_sequence_flows = sequence_flows(state)

                outgoing = Enum.map(outgoing, &process_sequence_flows[&1])

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

          {:error, error} ->
            Process.log(base_state.process, %Log.FlowNodeErrorOccurred{
              pid: self(),
              id: base_state.attrs["id"],
              token_id: token.token_id,
              error: error
            })

            {:noreply, handle_completion(state)}
        end
      end

      def handle_token({%BPXE.Token{} = token, _id}, state) do
        {:send, token, state}
      end

      def before_handle_token({_token, _id}, state) do
        {:ok, state}
      end

      def handle_completion(state) do
        state
      end

      def handle_recovery(recovered, state) do
        state = super(recovered, state)
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)
        base_state = get_state(state, BPXE.Engine.Base)

        process_sequence_flows = sequence_flows(state)

        Enum.reduce(flow_node_state.buffer, state, fn {_token_id, sequence_flow}, token ->
          send(process_sequence_flows[sequence_flow], token, state)
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
          base_state.attrs["id"],
          self(),
          saving_state
        )
      end

      defp commit_state(generation, state) do
        base_state = get_state(state, BPXE.Engine.Base)
        BPXE.Engine.Model.commit_state(base_state.model, generation, base_state.attrs["id"])
      end

      defp ack(%BPXE.Token{__generation__: 0}, _id, state) do
        commit_state(0, state)
      end

      defp ack(%BPXE.Token{token_id: token_id}, id, state) do
        base_state = get_state(state, BPXE.Engine.Base)

        BPXE.Channel.publish(
          {base_state.model.pid, :flow_sequence, id},
          {BPXE.Token.Ack, token_id, id}
        )
      end

      @initializer :init_flow_node

      def init_flow_node(state) do
        base_state = get_state(state, BPXE.Engine.Base)
        BPXE.Registry.register({base_state.model.pid, :flow_node, base_state.attrs["id"]})

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
      @ext_spec BPXE.BPMN.ext_spec()
      def send_token(sequence_flow, token, state) do
        alias BPXE.Engine.Process

        base_state = get_state(state, BPXE.Engine.Base)
        flow_node_state = get_state(state, BPXE.Engine.FlowNode)

        proceed =
          case sequence_flow[:conditionExpression] do
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
                    id: sequence_flow["id"],
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
            | buffer:
                Map.put(flow_node_state.buffer, {token.token_id, sequence_flow["id"]}, token)
          })
        else
          state
        end
      end

      def send(sequence_flow, token, state) do
        base_state = get_state(state, BPXE.Engine.Base)

        target = sequence_flow["targetRef"]

        case BPXE.Registry.whereis({base_state.model.pid, :flow_node, target}) do
          pid when is_pid(pid) ->
            send(pid, {token, sequence_flow["id"]})

          # FIXME: how should we handle this?
          nil ->
            :skip
        end

        state
      end

      def synthesize(state) do
        {:ok, state}
      end

      defp sequence_flows(state) do
        base_state = get_state(state, BPXE.Engine.Base)
        BPXE.Engine.Process.sequence_flows(base_state.process)
      end

      def get_input_data(id, state) do
        base_state = get_state(state, BPXE.Engine.Base)

        BPXE.Engine.Process.data_object(base_state.process, id)
        |> Result.map(fn
          data_object ->
            data_object.value
        end)
        |> Result.catch_error(:not_found, fn _ ->
          BPXE.Engine.PropertyContainer.get_property(base_state.process, id)
        end)
      end

      def set_input_data(id, value, token, state) do
        # There's nothing to set at this level, and we're not going
        # to go up
        {:error, :not_found}
      end

      def get_output_data(id, state) do
        # There's nothing we can currently find at a flow node
        # level
        {:error, :not_found}
      end

      def set_output_data(id, value, token, state) do
        base_state = get_state(state, BPXE.Engine.Base)

        BPXE.Engine.Process.data_object(base_state.process, id)
        |> Result.and_then(fn
          data_object ->
            case BPXE.Engine.Process.update_data_object(
                   base_state.process,
                   %{data_object | value: value},
                   token
                 ) do
              :ok -> {:ok, state}
            end
        end)
        |> Result.catch_error(:not_found, fn _ ->
          case BPXE.Engine.PropertyContainer.get_property(base_state.process, id) do
            {:error, :not_found} ->
              {:error, :not_found}

            {:ok, _value} ->
              case BPXE.Engine.PropertyContainer.set_property(
                     base_state.process,
                     id,
                     value,
                     token
                   ) do
                :ok -> {:ok, state}
                {:error, err} -> {:error, err}
              end
          end
        end)
      end

      defoverridable handle_recovery: 2,
                     before_handle_token: 2,
                     handle_token: 2,
                     handle_completion: 1,
                     send_token: 3,
                     send: 3,
                     synthesize: 1,
                     get_input_data: 2,
                     get_output_data: 2,
                     set_input_data: 4,
                     set_output_data: 4
    end
  end

  def whereis(model_pid, id) do
    BPXE.Registry.whereis({model_pid, :flow_node, id})
  end

  def get_outgoing(pid) do
    GenServer.call(pid, :get_outgoing)
  end

  def remove_outgoing(pid, name) do
    GenServer.call(pid, {:remove_outgoing, name})
  end

  def clear_outgoing(pid) do
    GenServer.call(pid, :clear_outgoing)
  end

  def remove_incoming(pid, name) do
    GenServer.call(pid, {:remove_incoming, name})
  end

  def get_incoming(pid) do
    GenServer.call(pid, :get_incoming)
  end

  def clear_incoming(pid) do
    GenServer.call(pid, :clear_incoming)
  end

  def synthesize(pid) do
    GenServer.call(pid, :synthesize)
  end

  import BPXE.Engine.BPMN

  def add_incoming(pid, attrs, body \\ nil) do
    add_node(pid, "incoming", attrs, body)
  end

  def add_outgoing(pid, attrs, body \\ nil) do
    add_node(pid, "outgoing", attrs, body)
  end
end
