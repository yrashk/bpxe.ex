defmodule BPEXE.Engine.ExclusiveGateway do
  use GenServer
  use BPEXE.Engine.FlowNode
  alias BPEXE.Engine.Process
  alias BPEXE.Engine.Process.Log

  defstate(
    [
      id: nil,
      options: %{},
      instance: nil,
      process: nil,
      tokens: %{},
      drop_tokens: %{},
      decision_made: false
    ],
    persist: ~w(tokens drop_tokens)a
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
    Process.log(state.process, %Log.ExclusiveGatewayActivated{
      pid: self(),
      id: state.id,
      token: msg.token
    })

    {:send, msg, state}
  end

  def send_message(sequence_flow, msg, %__MODULE__{decision_made: false} = state) do
    state1 = super(sequence_flow, msg, state)

    if Enum.any?(state1.buffer, fn {{token, _}, _} -> token == msg.token end) do
      %{state1 | decision_made: true}
    else
      state1
    end
  end

  def send_message(sequence_flow, msg, %__MODULE__{decision_made: true} = state) do
    super(sequence_flow, msg, state)
  end

  def send(sequence_flow, msg, %__MODULE__{decision_made: false} = state) do
    super(sequence_flow, msg, state)
  end

  def send(_sequence_flow, _msg, %__MODULE__{decision_made: true} = state) do
    state
  end

  def handle_completion(state) do
    %{state | decision_made: false}
  end
end
