defmodule BPXE.Engine.ParallelGateway do
  use GenServer
  use BPXE.Engine.FlowNode
  use BPXE.Engine.Blueprint.Recordable
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate token_ids: %{}, drop_tokens: %{}

  @persist_state :token_ids
  @persist_state :drop_tokens

  def start_link(id, options, blueprint, process) do
    GenServer.start_link(__MODULE__, {id, options, blueprint, process})
  end

  def init({id, options, blueprint, process}) do
    state =
      %__MODULE__{}
      |> put_state(Base, %{id: id, options: options, blueprint: blueprint, process: process})

    state = initialize(state)
    {:ok, state}
  end

  def handle_token({%BPXE.Token{} = token, id}, state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.ParallelGatewayReceived{
      pid: self(),
      id: base_state.id,
      token_id: token.token_id,
      from: id
    })

    flow_node_state = get_state(state, BPXE.Engine.FlowNode)

    case flow_node_state.incoming do
      [_] ->
        # only one incoming, we're done
        Process.log(base_state.process, %Log.ParallelGatewayCompleted{
          pid: self(),
          id: base_state.id,
          token_id: token.token_id,
          to: flow_node_state.outgoing
        })

        {:send, token, state}

      [] ->
        # there's a token but it couldn't come from anywhere. What gives?
        Process.log(base_state.process, %Log.ParallelGatewayCompleted{
          pid: self(),
          id: base_state.id,
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
            (base_state.options[{BPXE.BPMN.ext_spec(), "joinThreshold"}] ||
               "#{length(flow_node_state.incoming)}")
            |> String.to_integer()

          if length(tokens) == join_threshold do
            token_ids = Map.delete(token_ids, token.token_id)

            token = Enum.reduce(tl(tokens), token, &BPXE.Token.merge/2)

            Process.log(base_state.process, %Log.ParallelGatewayCompleted{
              pid: self(),
              id: base_state.id,
              token_id: token.token_id,
              to: flow_node_state.outgoing
            })

            {:send, token,
             %{
               state
               | token_ids: token_ids,
                 drop_tokens:
                   Map.put(
                     state.drop_tokens,
                     token.token_id,
                     length(flow_node_state.incoming) - join_threshold
                   )
             }}
          else
            {:dontsend, %{state | token_ids: token_ids}}
          end
        end
    end
  end
end
