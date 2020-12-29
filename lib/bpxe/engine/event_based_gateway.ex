defmodule BPXE.Engine.EventBasedGateway do
  use GenServer
  use BPXE.Engine.FlowNode
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate activated: nil
  @persist_state :activated

  def start_link(element, attrs, model, process) do
    start_link([{element, attrs, model, process}])
  end

  def init({_element, attrs, model, process}) do
    state =
      %__MODULE__{}
      |> put_state(Base, %{attrs: attrs, model: model, process: process})
      |> initialize()

    init_ack()
    enter_loop(state)
  end

  def handle_token(
        {%BPXE.Token{token_id: token_id} = token, _id},
        %__MODULE__{activated: nil} = state
      ) do
    base_state = get_state(state, BPXE.Engine.Base)

    Process.log(base_state.process, %Log.EventBasedGatewayActivated{
      pid: self(),
      id: base_state.attrs["id"],
      token_id: token.token_id
    })

    {:send, token, %{state | activated: token_id}}
  end
end
