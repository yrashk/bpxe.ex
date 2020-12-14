defmodule BPEXE.Proc.FlowNode do
  defmacro __using__(_options \\ []) do
    quote do
      import BPEXE.Proc.FlowNode, except: [add_outgoing: 2, add_incoming: 2]

      def handle_call({:add_incoming, id}, _from, state) do
        :syn.join({state.instance, :flow_out, id}, self())
        {:reply, {:ok, id}, %{state | incoming: [id | state.incoming]}}
      end

      def handle_call({:add_outgoing, id}, _from, state) do
        :syn.join({state.instance, :flow_back, id}, self())
        {:reply, {:ok, id}, %{state | outgoing: [id | state.outgoing]}}
      end

      def handle_info({%BPEXE.Message{} = msg, id}, state) do
        alias BPEXE.Proc.Process
        alias BPEXE.Proc.Process.Log

        Process.log(state.process, %Log.FlowNodeActivated{
          pid: self(),
          id: state.id,
          message: msg,
          token: msg.token
        })

        case handle_message({msg, id}, state) do
          {:send, new_msg, state} ->
            Process.log(state.process, %Log.FlowNodeForward{
              pid: self(),
              id: state.id,
              token: msg.token,
              to: state.outgoing
            })

            for wire <- state.outgoing do
              send_message(wire, new_msg, state)
            end

            {:noreply, state}

          {:send, new_msg, outgoing, state} ->
            Process.log(state.process, %Log.FlowNodeForward{
              pid: self(),
              id: state.id,
              token: msg.token,
              to: outgoing
            })

            for wire <- outgoing do
              send_message(wire, new_msg, state)
            end

            {:noreply, state}

          {:dontsend, state} ->
            Process.log(state.process, %Log.FlowNodeForward{
              pid: self(),
              id: state.id,
              token: msg.token,
              to: []
            })

            {:noreply, state}
        end
      end

      def handle_message({%BPEXE.Message{} = msg, _id}, state) do
        {:send, msg, state}
      end

      defoverridable handle_message: 2
    end
  end

  def send_message(wire, msg, state) do
    :syn.publish({state.instance, :flow_in, wire}, {msg, wire})
  end

  def send_message_back(wire, msg, state) do
    :syn.publish({state.instance, :flow_back, wire}, {msg, wire})
  end

  def add_outgoing(pid, name) do
    GenServer.call(pid, {:add_outgoing, name})
  end

  def add_incoming(pid, name) do
    GenServer.call(pid, {:add_incoming, name})
  end
end
