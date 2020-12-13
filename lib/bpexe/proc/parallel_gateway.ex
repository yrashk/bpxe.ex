defmodule BPEXE.Proc.ParallelGateway do
  use GenServer
  use BPEXE.Proc.FlowNode

  defstruct id: nil,
            options: %{},
            instance: nil,
            process: nil,
            outgoing: [],
            incoming: [],
            tokens: %{}

  def start_link(id, options, instance, process) do
    GenServer.start_link(__MODULE__, {id, options, instance, process})
  end

  def init({id, options, instance, process}) do
    {:ok, %__MODULE__{id: id, options: options, instance: instance, process: process}}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, state) do
    case state.incoming do
      [_] ->
        # only one incoming, we're done
        {:send, msg, state}

      [] ->
        # there's a message but it couldn't come from anywhere. What gives?
        {:dontsend, state}

      _ ->
        tokens = Map.update(state.tokens, msg.token, [msg], fn x -> [msg | x] end)
        messages = tokens[msg.token]

        if length(messages) == length(state.incoming) do
          tokens = Map.delete(tokens, msg.token)
          message = tl(messages) |> Enum.reduce(hd(messages), &BPEXE.Message.combine/2)
          {:send, message, %{state | tokens: tokens}}
        else
          {:dontsend, %{state | tokens: tokens}}
        end
    end
  end
end
