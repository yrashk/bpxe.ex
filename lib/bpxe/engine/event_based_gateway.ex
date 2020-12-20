defmodule BPXE.Engine.EventBasedGateway do
  use GenServer
  use BPXE.Engine.Blueprint.Recordable
  use BPXE.Engine.FlowNode
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate([id: nil, options: %{}, blueprint: nil, process: nil, activated: nil],
    persist: ~w(activated)a
  )

  def start_link(id, options, blueprint, process) do
    start_link([{id, options, blueprint, process}])
  end

  def init({id, options, blueprint, process}) do
    state =
      %__MODULE__{id: id, options: options, blueprint: blueprint, process: process}
      |> initialize()

    init_ack()
    enter_loop(state)
  end

  def handle_message(
        {%BPXE.Message{message_id: message_id} = msg, _id},
        %__MODULE__{activated: nil} = state
      ) do
    Process.log(state.process, %Log.EventBasedGatewayActivated{
      pid: self(),
      id: state.id,
      message_id: msg.message_id
    })

    {:send, msg, %{state | activated: message_id}}
  end
end
