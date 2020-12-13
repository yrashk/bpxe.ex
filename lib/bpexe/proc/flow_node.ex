defmodule BPEXE.Proc.FlowNode do
  defmacro __using__(_options \\ []) do
    quote do
      import BPEXE.Proc.FlowNode, except: [publish: 2, subscribe: 2]

      def handle_call({:subscribe, id}, _from, state) do
        :syn.join({state.instance, :flow_out, id}, self())
        {:reply, {:ok, id}, %{state | incoming: [id | state.incoming]}}
      end

      def handle_call({:publish, id}, _from, state) do
        :syn.join({state.instance, :flow_back, id}, self())
        {:reply, {:ok, id}, %{state | outgoing: [id | state.outgoing]}}
      end

      def handle_info({%BPEXE.Message{} = msg, id}, state) do
        IO.puts("#{inspect(state.id)} received #{inspect(msg)}")

        case handle_message({msg, id}, state) do
          {:send, new_msg, state} ->
            for wire <- state.outgoing do
              send_message(wire, new_msg, state)
            end

            {:noreply, state}

          {:send, new_msg, outgoing, state} ->
            for wire <- outgoing do
              send_message(wire, new_msg, state)
            end

            {:noreply, state}

          {:dontsend, state} ->
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

  def publish(pid, name) do
    GenServer.call(pid, {:publish, name})
  end

  def subscribe(pid, name) do
    GenServer.call(pid, {:subscribe, name})
  end
end
