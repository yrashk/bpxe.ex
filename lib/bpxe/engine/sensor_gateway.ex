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
  use BPXE.Engine.Blueprint.Recordable
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate([id: nil, options: %{}, blueprint: nil, process: nil, fired: []],
    persist: ~w(fired)a
  )

  def start_link(id, options, blueprint, process) do
    GenServer.start_link(__MODULE__, {id, options, blueprint, process})
  end

  def init({id, options, blueprint, process}) do
    state = %__MODULE__{id: id, options: options, blueprint: blueprint, process: process}
    state = initialize(state)
    {:ok, state}
  end

  defmodule Token do
    defstruct fired: [], token_id: nil
    use ExConstructor
  end

  def handle_token({%BPXE.Token{} = token, id}, state) do
    Process.log(state.process, %Log.SensorGatewayActivated{
      pid: self(),
      id: state.id,
      token_id: token.token_id
    })

    index = Enum.find_index(state.incoming, fn id_ -> id_ == id end)

    if index == 0 do
      # completion flow
      Process.log(state.process, %Log.SensorGatewayCompleted{
        pid: self(),
        id: state.id,
        token_id: token.token_id
      })

      {:send,
       BPXE.Token.new(
         activation: BPXE.Token.activation(token),
         payload: Token.new(fired: state.fired, token_id: token.token_id)
       ), [state.outgoing |> List.first()], %{state | fired: []}}
    else
      # regular flow
      {:send, token, [state.outgoing |> Enum.at(index)],
       %{state | fired: [length(state.incoming) - index - 1 | state.fired]}}
    end
  end
end
