defmodule BPEXE.Engine.PrecedenceGateway do
  @moduledoc """
  *Note: This gateway is not described in BPMN 2.0. Currently it can only be
  added programmatically (not through BPMN XML document, at this time)*

  This gateway will only process the first instance of a received message
  (token) and send it out to a corresponding output. The correspondance is
  achieved by requiring the same number of incoming and outgoing sequence
  flows. Outgoing sequence flows have to have an additional option
  `{BPEXE.spec_schema(), "correspondsTo"}` set to the name of the outgoing sequence
  flow.
  """
  use GenServer
  use BPEXE.Engine.FlowNode
  alias BPEXE.Engine.Process
  alias BPEXE.Engine.Process.Log

  defstate([id: nil, options: %{}, instance: nil, process: nil, precedence: %{}],
    persist: ~w(precedence)a
  )

  def start_link(id, options, instance, process) do
    GenServer.start_link(__MODULE__, {id, options, instance, process})
  end

  def init({id, options, instance, process}) do
    state = %__MODULE__{id: id, options: options, instance: instance, process: process}
    state = initialize(state)
    {:ok, state}
  end

  def handle_message({%BPEXE.Message{} = msg, id}, state) do
    Process.log(state.process, %Log.PrecedenceGatewayActivated{
      pid: self(),
      id: state.id,
      token: msg.token
    })

    case state.precedence[msg.token] do
      nil ->
        Process.log(state.process, %Log.PrecedenceGatewayPrecedenceEstablished{
          pid: self(),
          id: state.id,
          token: msg.token
        })

        state = %{state | precedence: Map.put(state.precedence, msg.token, [id])}

        case corresponds_to(id, state) do
          nil ->
            # There's no mapping between these flows
            # Drop the message
            {:dontsend, state}

          outgoing ->
            # There's a mapping, send it there
            {:send, msg, [outgoing], state}
        end

      precedence ->
        Process.log(state.process, %Log.PrecedenceGatewayMessageDiscarded{
          pid: self(),
          id: state.id,
          token: msg.token
        })

        new_precedence = [id | precedence]

        if length(new_precedence) == length(state.incoming) == length(state.outgoing) do
          # We've received them all, drop it from the state
          {:dontsend, %{state | precedence: Map.delete(state.precedence, msg.token)}}
        else
          # Drop the message
          {:dontsend, %{state | precedence: Map.put(state.precedence, msg.token, new_precedence)}}
        end
    end
  end

  defp corresponds_to(id, state) do
    {matched_id, _} =
      state.sequence_flows
      |> Enum.find(
        {nil, nil},
        fn {_, options} -> options[{BPEXE.spec_schema(), "correspondsTo"}] == id end
      )

    matched_id
  end
end
