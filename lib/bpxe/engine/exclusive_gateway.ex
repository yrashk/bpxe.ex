defmodule BPXE.Engine.ExclusiveGateway do
  use GenServer
  use BPXE.Engine.Model.Recordable
  use BPXE.Engine.FlowNode
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate token_ids: %{},
           drop_tokens: %{},
           decision_made: false

  @persist_state :token_ids
  @persist_state :drop_tokens

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

  def handle_token({%BPXE.Token{} = token, _id}, state) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.ExclusiveGatewayActivated{
      pid: self(),
      id: base_state.id,
      token_id: token.token_id
    })

    {:send, token, state}
  end

  def send_token(sequence_flow, token, %__MODULE__{decision_made: false} = state) do
    state1 = super(sequence_flow, token, state)
    flow_node_state = state1 |> get_state(FlowNode)

    if Enum.any?(flow_node_state.buffer, fn {{token_id, _}, _} -> token_id == token.token_id end) do
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
