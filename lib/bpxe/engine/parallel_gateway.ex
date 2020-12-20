defmodule BPXE.Engine.ParallelGateway do
  use GenServer
  use BPXE.Engine.FlowNode
  use BPXE.Engine.Blueprint.Recordable
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate(
    [id: nil, options: %{}, blueprint: nil, process: nil, token_ids: %{}, drop_tokens: %{}],
    persist: ~w(token_ids drop_tokens)a
  )

  def start_link(id, options, blueprint, process) do
    GenServer.start_link(__MODULE__, {id, options, blueprint, process})
  end

  def init({id, options, blueprint, process}) do
    state = %__MODULE__{id: id, options: options, blueprint: blueprint, process: process}
    state = initialize(state)
    {:ok, state}
  end

  def handle_token({%BPXE.Token{} = token, id}, state) do
    Process.log(state.process, %Log.ParallelGatewayReceived{
      pid: self(),
      id: state.id,
      token_id: token.token_id,
      from: id
    })

    case state.incoming do
      [_] ->
        # only one incoming, we're done
        Process.log(state.process, %Log.ParallelGatewayCompleted{
          pid: self(),
          id: state.id,
          token_id: token.token_id,
          to: state.outgoing
        })

        {:send, token, state}

      [] ->
        # there's a token but it couldn't come from anywhere. What gives?
        Process.log(state.process, %Log.ParallelGatewayCompleted{
          pid: self(),
          id: state.id,
          token_id: token.token_id,
          to: []
        })

        {:dontsend, state}

      _ ->
        # Join

        # If join threshold was already reached, drop a token
        drop_token = state.drop_tokens[token.token_id]

        if !!drop_token do
          drop_token = drop_token - 1

          drop_tokens =
            if drop_token == 0 do
              Map.delete(state.drop_tokens, token.token_id)
            else
              Map.put(state.drop_tokens, token.token_id, drop_token)
            end

          {:dontsend, %{state | drop_tokens: drop_tokens}}
        else
          token_ids =
            Map.update(state.token_ids, token.token_id, [token], fn x -> [token | x] end)

          tokens = token_ids[token.token_id]

          join_threshold =
            (state.options[{BPXE.BPMN.ext_spec(), "joinThreshold"}] || "#{length(state.incoming)}")
            |> String.to_integer()

          if length(tokens) == join_threshold do
            token_ids = Map.delete(token_ids, token.token_id)

            token = %{hd(tokens) | payload: Enum.map(tokens, fn m -> m.payload end)}

            Process.log(state.process, %Log.ParallelGatewayCompleted{
              pid: self(),
              id: state.id,
              token_id: token.token_id,
              to: state.outgoing
            })

            {:send, token,
             %{
               state
               | token_ids: token_ids,
                 drop_tokens:
                   Map.put(
                     state.drop_tokens,
                     token.token_id,
                     length(state.incoming) - join_threshold
                   )
             }}
          else
            {:dontsend, %{state | token_ids: token_ids}}
          end
        end
    end
  end
end
