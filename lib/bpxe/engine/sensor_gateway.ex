defmodule BPXE.Engine.SensorGateway do
  @moduledoc """
  *Note: This gateway is not described in BPMN 2.0. Currently it can only be
  added programmatically (not through BPMN XML document, at this time)*

  This gateway senses which of first N-1 incoming sequence flows fired (i.e.
  their conditions were truthful) [where N is the total number of incoming
  sequence flows], maps these N-1 incoming sequence flows to first N-1 outgoing
  sequence flows, and once Nth incoming sequence fires, it sends 0-based
  indices of incoming sequences fired
  to Nth outgoing sequence flow.

  This gateway is used to facilitate things like `BPXE.Engine.InclusiveGateway`
  """
  use GenServer
  use BPXE.Engine.FlowNode
  use BPXE.Engine.Model.Recordable
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate fired: []
  @persist_state :fired

  def start_link(id, attrs, model, process) do
    GenServer.start_link(__MODULE__, {id, attrs, model, process})
  end

  def init({id, attrs, model, process}) do
    state =
      %__MODULE__{}
      |> put_state(Base, %{id: id, attrs: attrs, model: model, process: process})

    state = initialize(state)
    {:ok, state}
  end

  defmodule Token do
    defstruct fired: [], token_id: nil
    use ExConstructor
  end

  def handle_token({%BPXE.Token{} = token, id}, state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.SensorGatewayActivated{
      pid: self(),
      id: base_state.id,
      token_id: token.token_id
    })

    flow_node_state = get_state(state, BPXE.Engine.FlowNode)

    index = Enum.find_index(flow_node_state.incoming, fn id_ -> id_ == id end)

    if index == 0 do
      # completion flow
      Process.log(base_state.process, %Log.SensorGatewayCompleted{
        pid: self(),
        id: base_state.id,
        token_id: token.token_id
      })

      {:send,
       BPXE.Token.new(
         activation: BPXE.Token.activation(token),
         payload: Token.new(fired: state.fired, token_id: token.token_id)
       ), [flow_node_state.outgoing |> List.first()], %{state | fired: []}}
    else
      # regular flow
      {:send, token, [flow_node_state.outgoing |> Enum.at(index)],
       %{state | fired: [length(flow_node_state.incoming) - index - 1 | state.fired]}}
    end
  end
end
