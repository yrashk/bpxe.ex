defmodule BPEXE.Engine.EventBasedGateway do
  use GenServer
  use BPEXE.Engine.FlowNode
  alias BPEXE.Engine.Process
  alias BPEXE.Engine.Process.Log

  defstate([id: nil, options: %{}, instance: nil, process: nil, activated: nil],
    persist: ~w(activated)a
  )

  def start_link(id, options, instance, process) do
    start_link([{id, options, instance, process}])
  end

  def init({id, options, instance, process}) do
    state =
      %__MODULE__{id: id, options: options, instance: instance, process: process}
      |> initialize()

    init_ack()
    enter_loop(state)
  end

  def handle_message(
        {%BPEXE.Message{message_id: message_id} = msg, _id},
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
