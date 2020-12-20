defmodule BPXE.Engine.InclusiveGateway do
  alias BPXE.Engine.{Process, FlowNode, Base}
  alias BPXE.Engine.Process.Log
  use BPXE.Engine.Blueprint.Recordable
  use GenServer
  use FlowNode

  defstate(
    [
      id: nil,
      options: %{},
      blueprint: nil,
      process: nil,
      fired: nil,
      incoming_tokens: [],
      synthesized: false
    ],
    persist: ~w(fired incoming_tokens)a
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
    Process.log(state.process, %Log.InclusiveGatewayReceived{
      pid: self(),
      id: state.id,
      token_id: token.token_id,
      from: id
    })

    case state.incoming do
      [_] ->
        # only one incoming, we're done (fork)
        Process.log(state.process, %Log.InclusiveGatewayCompleted{
          pid: self(),
          id: state.id,
          token_id: token.token_id
        })

        {:send, token, state}

      [] ->
        # there's a token but it couldn't come from anywhere. What gives?
        Process.log(state.process, %Log.InclusiveGatewayCompleted{
          pid: self(),
          id: state.id,
          token_id: nil
        })

        {:dontsend, state}

      _ ->
        # Join

        index = Enum.find_index(state.incoming, fn x -> x == id end)

        if index == 0 do
          # completion token
          try_complete(%__MODULE__{state | fired: token})
        else
          incoming_tokens = [{token, id} | state.incoming_tokens]
          try_complete(%__MODULE__{state | incoming_tokens: incoming_tokens})
        end
    end
  end

  defp try_complete(%__MODULE__{fired: nil} = state) do
    {:dontsend, state}
  end

  defp try_complete(
         %__MODULE__{
           fired: fired_token,
           incoming_tokens: incoming_tokens,
           # don't include sensor wire
           incoming: [_ | incoming]
         } = state
       ) do
    incoming = incoming |> Enum.reverse()

    all_fired? =
      Enum.all?(fired_token.payload.fired, fn index ->
        flow_id = incoming |> Enum.at(index)

        Enum.find(incoming_tokens, fn {token, id} ->
          id == flow_id and token.token_id == fired_token.payload.token_id
        end)
      end)

    if all_fired? do
      Process.log(state.process, %Log.InclusiveGatewayCompleted{
        pid: self(),
        id: state.id,
        token_id: fired_token.payload.token_id,
        fired:
          fired_token.payload.fired
          |> Enum.zip(state.incoming |> tl() |> Enum.reverse())
          |> Enum.map(fn {_index, seq_flow} -> seq_flow end)
      })

      {out_token, _} =
        Enum.find(incoming_tokens, fn {token, _} ->
          token.token_id == fired_token.payload.token_id
        end)

      out_token =
        Enum.reduce(incoming_tokens, %{out_token | payload: %{}}, fn {token, _}, acc ->
          if token.token_id == out_token.token_id do
            BPXE.Token.merge(acc, token)
          else
            acc
          end
        end)

      {:send, out_token, %{state | fired: nil, incoming_tokens: []}}
    else
      {:dontsend, state}
    end
  end

  alias :digraph, as: G
  alias :digraph_utils, as: GU

  def synthesize(%__MODULE__{synthesized: true} = state) do
    super(state)
  end

  def synthesize(%__MODULE__{process: process, synthesized: false} = state) do
    super(state)
    |> Result.map(fn state ->
      # Here we need to find if there was a shared fork earlier in the flow
      case state.incoming do
        [] ->
          # nothing incoming, no shared fork
          {:ok, state}

        _predecessors ->
          # at least one incoming, this means that it might be a join (even if
          # it's one -- a fork-condition-<something>-join, still should skip it
          # if the condition was not satisfied)
          g = G.new()
          G.add_vertex(g, state.id)

          if build_graph(g, state.id, state) == :found do
            fork_id = GU.topsort(g) |> List.first()
            fork = FlowNode.whereis(state.blueprint.pid, fork_id)
            gw_id = {:synthesized_sensor_gateway, fork_id}
            {:ok, gw} = Process.add_sensor_gateway(process, gw_id, %{"id" => gw_id})
            outgoing = FlowNode.get_outgoing(fork)
            FlowNode.clear_outgoing(fork)

            # Rewire outgoing
            sequence_flows = FlowNode.get_sequence_flows(fork)
            FlowNode.clear_sequence_flows(fork)

            for sequence_flow <- outgoing do
              {_, options} = Enum.find(sequence_flows, fn {k, _} -> k == sequence_flow end)
              successor = FlowNode.whereis(state.blueprint.pid, options["targetRef"])
              in_flow_id = {:synthesized_sequence_flow, {:in, sequence_flow}}
              FlowNode.remove_incoming(successor, sequence_flow)
              FlowNode.add_outgoing(fork, in_flow_id)
              FlowNode.add_incoming(gw, in_flow_id)

              FlowNode.add_sequence_flow(fork, in_flow_id, %{
                "id" => in_flow_id,
                "sourceRef" => fork_id,
                "targetRef" => gw_id,
                :conditionExpression => options[:conditionExpression]
              })

              out_flow_id = {:synthesized_sequence_flow, {:out, sequence_flow}}

              FlowNode.add_incoming(successor, out_flow_id)
              FlowNode.add_outgoing(gw, out_flow_id)

              FlowNode.add_sequence_flow(gw, out_flow_id, %{
                "id" => out_flow_id,
                "sourceRef" => gw_id,
                "targetRef" => options["targetRef"]
              })
            end

            # Add a completion flow to fork
            completion_id = {:synthesized_sequence_flow_completion, gw_id}
            FlowNode.add_outgoing(fork, completion_id)
            FlowNode.add_incoming(gw, completion_id)

            FlowNode.add_sequence_flow(fork, completion_id, %{
              "id" => completion_id,
              "sourceRef" => fork_id,
              "targetRef" => gw_id
            })

            # Add a completion flow to sensor
            sensor_to_gateway_id = {:synethesized_senquence_flow_sensor, gw_id}
            FlowNode.add_outgoing(gw, sensor_to_gateway_id)

            FlowNode.add_sequence_flow(gw, sensor_to_gateway_id, %{
              "id" => sensor_to_gateway_id,
              "sourceRef" => gw_id,
              "targetRef" => state.id
            })

            %{state | incoming: [sensor_to_gateway_id | state.incoming], synthesized: true}
          else
            state
          end
      end
    end)
  end

  defp incoming(current, %__MODULE__{incoming: incoming, id: current}),
    do: incoming

  defp incoming(current, %__MODULE__{blueprint: blueprint}),
    do: FlowNode.whereis(blueprint.pid, current) |> FlowNode.get_incoming()

  defp find_predecessor(sequence_flow, %__MODULE__{blueprint: blueprint}) do
    :syn.get_members({blueprint.pid, :flow_sequence, sequence_flow})
    |> Enum.map(fn node -> {node, Base.module(node)} end)
    |> List.first()
  end

  defp build_graph(g, current, %__MODULE__{} = state) do
    Enum.reduce(incoming(current, state), nil, fn flow, _acc ->
      {node, module} = find_predecessor(flow, state)
      pred_id = node |> Base.id()
      G.add_vertex(g, pred_id)
      G.add_edge(g, pred_id, current, flow)

      if module == __MODULE__ do
        # We found an inclusive gateway, stop building this branch
        :found
      else
        build_graph(g, pred_id, state)
      end
    end)
  end
end
