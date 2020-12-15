defmodule BPEXE.Proc.FlowNode do
  defmacro __using__(_options \\ []) do
    quote do
      import BPEXE.Proc.FlowNode,
        only: [send_message: 3, send_message_back: 3, defstate: 1, defstate: 2]

      def handle_call({:add_incoming, id}, _from, state) do
        :syn.join({state.instance.pid, :flow_out, id}, self())
        {:reply, {:ok, id}, %{state | incoming: [id | state.incoming]}}
      end

      def handle_call({:add_outgoing, id}, _from, state) do
        :syn.join({state.instance.pid, :flow_back, id}, self())
        {:reply, {:ok, id}, %{state | outgoing: [id | state.outgoing]}}
      end

      def handle_info({%BPEXE.Message{__invisible__: invisible} = msg, id}, state) do
        alias BPEXE.Proc.Process
        alias BPEXE.Proc.Process.Log

        if !invisible,
          do:
            Process.log(state.process, %Log.FlowNodeActivated{
              pid: self(),
              id: state.id,
              message: msg,
              token: msg.token
            })

        case handle_message({msg, id}, state) do
          {:send, %BPEXE.Message{__invisible__: invisible} = new_msg, state} ->
            if !invisible,
              do:
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

            save_state(state)

            ack(msg, id, state)

            {:noreply, handle_completion(state)}

          {:send, %BPEXE.Message{__invisible__: invisible} = new_msg, outgoing, state} ->
            if !invisible,
              do:
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

            save_state(state)

            ack(msg, id, state)

            {:noreply, handle_completion(state)}

          {:dontsend, state} ->
            if !invisible,
              do:
                Process.log(state.process, %Log.FlowNodeForward{
                  pid: self(),
                  id: state.id,
                  token: msg.token,
                  to: []
                })

            save_state(state)

            ack(msg, id, state)

            {:noreply, handle_completion(state)}
        end
      end

      def handle_message({%BPEXE.Message{} = msg, _id}, state) do
        {:send, msg, state}
      end

      def handle_completion(state) do
        state
      end

      defoverridable handle_message: 2, handle_completion: 1

      defp save_state(state) do
        state_map = Map.from_struct(state)

        saving_state =
          Enum.reduce(persisted_state(), %{}, fn key, acc ->
            Map.put(acc, key, state_map[key])
          end)

        BPEXE.Proc.Instance.save_state(state.instance, state.id, self(), saving_state)
      end

      defp ack(%BPEXE.Message{__invisible__: true}, _id, _state) do
        :skip
      end

      defp ack(%BPEXE.Message{token: token}, id, state) do
        :syn.publish({state.instance.pid, :flow_in, id}, {BPEXE.Message.Ack, token, id})
      end
    end
  end

  def send_message(wire, msg, state) do
    :syn.publish({state.instance.pid, :flow_in, wire}, {msg, wire})
    state
  end

  def send_message_back(wire, msg, state) do
    :syn.publish({state.instance.pid, :flow_back, wire}, {msg, wire})
    state
  end

  def add_outgoing(pid, name) do
    GenServer.call(pid, {:add_outgoing, name})
  end

  def add_incoming(pid, name) do
    GenServer.call(pid, {:add_incoming, name})
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
        outgoing: []
      })
      |> Map.to_list()

    quote bind_quoted: [struct: struct, persist: persist] do
      defstruct struct

      defp persisted_state, do: unquote(persist)
    end
  end
end
