defmodule BPXE.Engine.InclusiveGateway do
  alias BPXE.Engine.{Process, FlowNode, Base}
  alias BPXE.Engine.Process.Log
  use GenServer
  use FlowNode

  defstate(
    [
      id: nil,
      options: %{},
      instance: nil,
      process: nil,
      fired: nil,
      incoming_messages: [],
      synthesized: false
    ],
    persist: ~w(fired incoming_messages)a
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
    Process.log(state.process, %Log.InclusiveGatewayReceived{
      pid: self(),
      id: state.id,
      message_id: msg.message_id,
      from: id
    })

    case state.incoming do
      [_] ->
        # only one incoming, we're done (fork)
        Process.log(state.process, %Log.InclusiveGatewayCompleted{
          pid: self(),
          id: state.id,
          message_id: msg.message_id
        })

        {:send, msg, state}

      [] ->
        # there's a message but it couldn't come from anywhere. What gives?
        Process.log(state.process, %Log.InclusiveGatewayCompleted{
          pid: self(),
          id: state.id,
          message_id: nil
        })

        {:dontsend, state}

      _ ->
        # Join

        index = Enum.find_index(state.incoming, fn x -> x == id end)

        if index == 0 do
          # completion message
          try_complete(%__MODULE__{state | fired: msg})
        else
          incoming_messages = [{msg, id} | state.incoming_messages]
          try_complete(%__MODULE__{state | incoming_messages: incoming_messages})
        end
    end
  end

  defp try_complete(%__MODULE__{fired: nil} = state) do
    {:dontsend, state}
  end

  defp try_complete(
         %__MODULE__{
           fired: fired_msg,
           incoming_messages: incoming_messages,
           # don't include sensor wire
           incoming: [_ | incoming]
         } = state
       ) do
    incoming = incoming |> Enum.reverse()

    all_fired? =
      Enum.all?(fired_msg.content.fired, fn index ->
        flow_id = incoming |> Enum.at(index)

        Enum.find(incoming_messages, fn {msg, id} ->
          id == flow_id and msg.message_id == fired_msg.content.message_id
        end)
      end)

    if all_fired? do
      Process.log(state.process, %Log.InclusiveGatewayCompleted{
        pid: self(),
        id: state.id,
        message_id: fired_msg.content.message_id,
        fired:
          fired_msg.content.fired
          |> Enum.zip(state.incoming |> tl() |> Enum.reverse())
          |> Enum.map(fn {_index, seq_flow} -> seq_flow end)
      })

      {out_msg, _} =
        Enum.find(incoming_messages, fn {msg, _} ->
          msg.message_id == fired_msg.content.message_id
        end)

      content =
        Enum.reduce(incoming_messages, [], fn {msg, _}, acc ->
          if msg.message_id == out_msg.message_id do
            [msg.content | acc]
          else
            acc
          end
        end)
        |> Enum.reverse()

      out_msg = %{out_msg | content: content}

      {:send, out_msg, %{state | fired: nil, incoming_messages: []}}
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
            fork = FlowNode.whereis(state.instance.pid, fork_id)
            gw_id = {:synthesized_sensor_gateway, fork_id}
            {:ok, gw} = Process.add_sensor_gateway(process, gw_id, %{"id" => gw_id})
            outgoing = FlowNode.get_outgoing(fork)
            FlowNode.clear_outgoing(fork)

            # Rewire outgoing
            sequence_flows = FlowNode.get_sequence_flows(fork)
            FlowNode.clear_sequence_flows(fork)

            for sequence_flow <- outgoing do
              {_, options} = Enum.find(sequence_flows, fn {k, _} -> k == sequence_flow end)
              successor = FlowNode.whereis(state.instance.pid, options["targetRef"])
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

  defp incoming(current, %__MODULE__{incoming: incoming, id: current} = state),
    do: incoming

  defp incoming(current, %__MODULE__{instance: instance} = state),
    do: FlowNode.whereis(instance.pid, current) |> FlowNode.get_incoming()

  defp outgoing(current, %__MODULE__{outgoing: outgoing, id: current} = state),
    do: outgoing

  defp outgoing(current, %__MODULE__{process: process} = state) when is_pid(current),
    do: FlowNode.get_outgoing(current)

  defp find_predecessor(sequence_flow, %__MODULE__{instance: instance} = state) do
    :syn.get_members({instance.pid, :flow_sequence, sequence_flow})
    |> Enum.map(fn node -> {node, Base.module(node)} end)
    |> List.first()
  end

  defp build_graph(g, current, %__MODULE__{process: process, id: id} = state) do
    Enum.reduce(incoming(current, state), nil, fn flow, acc ->
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
