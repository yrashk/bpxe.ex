defmodule BPXE.Engine.ParallelGateway do
  use GenServer
  use BPXE.Engine.FlowNode
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate([id: nil, options: %{}, instance: nil, process: nil, message_ids: %{}, drop_messages: %{}],
    persist: ~w(message_ids drop_messages)a
  )

  def start_link(id, options, instance, process) do
    GenServer.start_link(__MODULE__, {id, options, instance, process})
  end

  def init({id, options, instance, process}) do
    state = %__MODULE__{id: id, options: options, instance: instance, process: process}
    state = initialize(state)
    {:ok, state}
  end

  def handle_message({%BPXE.Message{} = msg, id}, state) do
    Process.log(state.process, %Log.ParallelGatewayReceived{
      pid: self(),
      id: state.id,
      message_id: msg.message_id,
      from: id
    })

    case state.incoming do
      [_] ->
        # only one incoming, we're done
        Process.log(state.process, %Log.ParallelGatewayCompleted{
          pid: self(),
          id: state.id,
          message_id: msg.message_id,
          to: state.outgoing
        })

        {:send, msg, state}

      [] ->
        # there's a message but it couldn't come from anywhere. What gives?
        Process.log(state.process, %Log.ParallelGatewayCompleted{
          pid: self(),
          id: state.id,
          message_id: msg.message_id,
          to: []
        })

        {:dontsend, state}

      _ ->
        # Join

        # If join threshold was already reached, drop a message
        drop_message = state.drop_messages[msg.message_id]

        if !!drop_message do
          drop_message = drop_message - 1

          drop_messages =
            if drop_message == 0 do
              Map.delete(state.drop_messages, msg.message_id)
            else
              Map.put(state.drop_messages, msg.message_id, drop_message)
            end

          {:dontsend, %{state | drop_messages: drop_messages}}
        else
          message_ids = Map.update(state.message_ids, msg.message_id, [msg], fn x -> [msg | x] end)
          messages = message_ids[msg.message_id]

          join_threshold =
            (state.options[{BPXE.BPMN.ext_spec(), "joinThreshold"}] || "#{length(state.incoming)}")
            |> String.to_integer()

          if length(messages) == join_threshold do
            message_ids = Map.delete(message_ids, msg.message_id)

            message = %{hd(messages) | content: Enum.map(messages, fn m -> m.content end)}

            Process.log(state.process, %Log.ParallelGatewayCompleted{
              pid: self(),
              id: state.id,
              message_id: msg.message_id,
              to: state.outgoing
            })

            {:send, message,
             %{
               state
               | message_ids: message_ids,
                 drop_messages:
                   Map.put(
                     state.drop_messages,
                     msg.message_id,
                     length(state.incoming) - join_threshold
                   )
             }}
          else
            {:dontsend, %{state | message_ids: message_ids}}
          end
        end
    end
  end
end
