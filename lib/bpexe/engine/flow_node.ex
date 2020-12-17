defmodule BPEXE.Engine.FlowNode do
  defmacro __using__(_options \\ []) do
    quote do
      use BPEXE.Engine.Base
      use BPEXE.Engine.Recoverable

      import BPEXE.Engine.FlowNode,
        only: [send_message: 3, send: 3, defstate: 1, defstate: 2]

      def handle_call({:add_incoming, id}, _from, state) do
        :syn.join({state.instance.pid, :flow_out, id}, self())
        {:reply, {:ok, id}, %{state | incoming: [id | state.incoming]}}
      end

      def handle_call(:clear_incoming, _from, state) do
        for flow <- state.incoming do
          :syn.leave({state.instance.pid, :flow_out, flow}, self())
        end

        {:reply, :ok, %{state | incoming: []}}
      end

      def handle_call({:remove_incoming, id}, _from, state) do
        :syn.leave({state.instance.pid, :flow_out, id}, self())
        {:reply, :ok, %{state | incoming: state.incoming -- [id]}}
      end

      def handle_call({:add_outgoing, id}, _from, state) do
        :syn.join({state.instance.pid, :flow_back, id}, self())
        {:reply, {:ok, id}, %{state | outgoing: [id | state.outgoing]}}
      end

      def handle_call({:remove_outgoing, id}, _from, state) do
        :syn.leave({state.instance.pid, :flow_back, id}, self())
        {:reply, :ok, %{state | outgoing: state.outgoing -- [id]}}
      end

      def handle_call(:clear_outgoing, _from, state) do
        for flow <- state.outgoing do
          :syn.leave({state.instance.pid, :flow_back, flow}, self())
        end

        {:reply, :ok, %{state | outgoing: []}}
      end

      def handle_call({:add_sequence_flow, id, options}, _from, state) do
        :syn.join({state.instance.pid, :flow_sequence, id}, self())

        {:reply, {:ok, {state.process, :sequence_flow, id}},
         %{state | sequence_flows: Map.put(state.sequence_flows, id, options)}}
      end

      def handle_call({:remove_sequence_flow, id}, _from, state) do
        :syn.leave({state.instance.pid, :flow_sequence, id}, self())

        {:reply, Map.get(state.sequence_flows, id),
         %{state | sequence_flows: Map.delete(state.sequence_flows, id)}}
      end

      def handle_call(:get_sequence_flows, _from, state) do
        {:reply, state.sequence_flows, state}
      end

      def handle_call(:get_incoming, _from, state) do
        {:reply, state.incoming, state}
      end

      def handle_call(:get_outgoing, _from, state) do
        {:reply, state.outgoing, state}
      end

      def handle_info({BPEXE.Message.Ack, token, id}, state) do
        case Map.get(state.buffer, {token, id}) do
          %BPEXE.Message{__txn__: txn} ->
            state = %{state | buffer: Map.delete(state.buffer, {token, id})}
            save_state(txn, state)
            # if this message has been delivered to all recipients
            unless Enum.any?(state.buffer, fn {{t, _}, _} -> t == token end) do
              # commit
              commit_state(txn, state)
            end

            {:noreply, state}

          nil ->
            {:noreply, state}
        end
      end

      def handle_info({%BPEXE.Message{__txn__: txn} = msg, id}, state) do
        alias BPEXE.Engine.Process
        alias BPEXE.Engine.Process.Log

        Process.log(state.process, %Log.FlowNodeActivated{
          pid: self(),
          id: state.id,
          message: msg,
          token: msg.token
        })

        case handle_message({msg, id}, state) do
          {:send, %BPEXE.Message{} = new_msg, state} ->
            new_msg = %{
              new_msg
              | __txn__: if(txn == new_msg.__txn__, do: next_txn(new_msg), else: new_msg.__txn__)
            }

            Process.log(state.process, %Log.FlowNodeForward{
              pid: self(),
              id: state.id,
              token: msg.token,
              to: state.outgoing
            })

            state =
              Enum.reduce(state.outgoing, state, fn wire, state ->
                send_message(wire, new_msg, state)
              end)

            save_state(txn, state)
            ack(msg, id, state)

            {:noreply, handle_completion(state)}

          {:send, %BPEXE.Message{} = new_msg, outgoing, state} ->
            new_msg = %{
              new_msg
              | __txn__: if(txn == new_msg.__txn__, do: next_txn(new_msg), else: new_msg.__txn__)
            }

            Process.log(state.process, %Log.FlowNodeForward{
              pid: self(),
              id: state.id,
              token: msg.token,
              to: outgoing
            })

            state =
              Enum.reduce(outgoing, state, fn wire, state ->
                send_message(wire, new_msg, state)
              end)

            save_state(txn, state)
            ack(msg, id, state)

            {:noreply, handle_completion(state)}

          {:dontsend, state} ->
            save_state(txn, state)
            ack(msg, id, state)

            {:noreply, handle_completion(state)}

          {:dontack, state} ->
            {:noreply, handle_completion(state)}
        end
      end

      def handle_message({%BPEXE.Message{} = msg, _id}, state) do
        {:send, msg, state}
      end

      def handle_completion(state) do
        state
      end

      def handle_recovery(recovered, state) do
        state = super(recovered, state)

        Enum.reduce(state.buffer, state, fn {{_token, wire}, msg} ->
          send(wire, msg, state)
        end)
      end

      defoverridable handle_message: 2, handle_completion: 1

      defp next_txn(%BPEXE.Message{} = msg) do
        BPEXE.Message.next_txn(msg)
      end

      defp save_state(txn, state) do
        state_map = Map.from_struct(state)

        saving_state =
          Enum.reduce(persisted_state(), %{}, fn key, acc ->
            Map.put(acc, key, state_map[key])
          end)

        BPEXE.Engine.Instance.save_state(state.instance, txn, state.id, self(), saving_state)
      end

      defp commit_state(txn, state) do
        BPEXE.Engine.Instance.commit_state(state.instance, txn, state.id)
      end

      defp ack(%BPEXE.Message{__txn__: 0}, _id, state) do
        commit_state(0, state)
      end

      defp ack(%BPEXE.Message{token: token}, id, state) do
        :syn.publish({state.instance.pid, :flow_sequence, id}, {BPEXE.Message.Ack, token, id})
      end

      @initializer :init_flow_node

      def init_flow_node(state) do
        :syn.register({state.instance.pid, :flow_node, state.id}, self())
        state
      end

      def flow_node?() do
        true
      end
    end
  end

  def send_message(wire, msg, state) do
    send(wire, msg, state)
    %{state | buffer: Map.put(state.buffer, {msg.token, wire}, msg)}
  end

  def send(wire, msg, state) do
    target = state.sequence_flows[wire]["targetRef"]

    case :syn.whereis({state.instance.pid, :flow_node, target}) do
      pid when is_pid(pid) ->
        send(pid, {msg, wire})

      # FIXME: how should we handle this?
      :undefined ->
        :skip
    end

    state
  end

  def whereis(instance_pid, id) do
    case :syn.whereis({instance_pid, :flow_node, id}) do
      :undefined -> nil
      pid when is_pid(pid) -> pid
    end
  end

  def add_outgoing(pid, name) do
    GenServer.call(pid, {:add_outgoing, name})
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

  def add_incoming(pid, name) do
    GenServer.call(pid, {:add_incoming, name})
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

  def add_sequence_flow(pid, id, options) do
    GenServer.call(pid, {:add_sequence_flow, id, options})
  end

  def get_sequence_flows(pid) do
    GenServer.call(pid, :get_sequence_flows)
  end

  def remove_sequence_flow(pid, id) do
    GenServer.call(pid, {:remove_sequence_flow, id})
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
        buffer: Macro.escape(%{})
      })
      |> Map.to_list()

    persist = [:buffer | persist] |> Enum.uniq()

    quote bind_quoted: [struct: struct, persist: persist] do
      defstruct struct

      defp persisted_state, do: unquote(persist)
    end
  end
end
