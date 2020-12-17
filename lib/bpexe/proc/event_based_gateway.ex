defmodule BPEXE.Proc.EventBasedGateway do
  use GenServer
  use BPEXE.Proc.FlowNode
  alias BPEXE.Proc.Process
  alias BPEXE.Proc.Process.Log

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
        {%BPEXE.Message{__invisible__: true, token: token} = msg, id},
        %__MODULE__{activated: token} = state
      ) do
    Process.log(state.process, %Log.EventBasedGatewayCompleted{
      pid: self(),
      id: state.id,
      token: msg.token,
      to: id
    })

    {:send, %{msg | properties: Map.put(msg.properties, {__MODULE__, :route}, id)},
     %{state | activated: nil}}
  end

  def handle_message(
        {%BPEXE.Message{token: token} = msg, _id},
        %__MODULE__{activated: nil} = state
      ) do
    Process.log(state.process, %Log.EventBasedGatewayActivated{
      pid: self(),
      id: state.id,
      token: msg.token
    })

    {:send, msg, %{state | activated: token}}
  end
end
