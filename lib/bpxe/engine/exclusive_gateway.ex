defmodule BPXE.Engine.ExclusiveGateway do
  use GenServer
  use BPXE.Engine.Blueprint.Recordable
  use BPXE.Engine.FlowNode
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate(
    [
      id: nil,
      options: %{},
      blueprint: nil,
      process: nil,
      token_ids: %{},
      drop_tokens: %{},
      decision_made: false
    ],
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

  def handle_token({%BPXE.Token{} = token, _id}, state) do
    Process.log(state.process, %Log.ExclusiveGatewayActivated{
      pid: self(),
      id: state.id,
      token_id: token.token_id
    })

    {:send, token, state}
  end

  def send_token(sequence_flow, token, %__MODULE__{decision_made: false} = state) do
    state1 = super(sequence_flow, token, state)

    if Enum.any?(state1.buffer, fn {{token_id, _}, _} -> token_id == token.token_id end) do
      %{state1 | decision_made: true}
    else
      state1
    end
  end

  def send_token(sequence_flow, token, %__MODULE__{decision_made: true} = state) do
    super(sequence_flow, token, state)
  end

  def send(sequence_flow, token, %__MODULE__{decision_made: false} = state) do
    super(sequence_flow, token, state)
  end

  def send(_sequence_flow, _token, %__MODULE__{decision_made: true} = state) do
    state
  end

  def handle_completion(state) do
    %{state | decision_made: false}
  end
end
