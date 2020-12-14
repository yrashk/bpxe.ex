defmodule BPEXE.Proc.EventBasedGateway do
  use GenServer
  use BPEXE.Proc.FlowNode
  alias BPEXE.Proc.Process
  alias BPEXE.Proc.Process.Log

  defstruct id: nil,
            options: %{},
            instance: nil,
            process: nil,
            outgoing: [],
            incoming: [],
            activated: nil

  def start_link(id, options, instance, process) do
    GenServer.start_link(__MODULE__, {id, options, instance, process})
  end

  def init({id, options, instance, process}) do
    {:ok, %__MODULE__{id: id, options: options, instance: instance, process: process}}
  end

  def handle_message({%BPEXE.Message{} = msg, _id}, %__MODULE__{activated: nil} = state) do
    Process.log(state.process, %Log.EventBasedGatewayActivated{
      pid: self(),
      id: state.id,
      token: msg.token
    })

    {:send, msg, %{state | activated: msg}}
  end

  def handle_message({%BPEXE.Message{} = msg, id}, %__MODULE__{activated: msg} = state) do
    Process.log(state.process, %Log.EventBasedGatewayCompleted{
      pid: self(),
      id: state.id,
      token: msg.token,
      to: id
    })

    {:send, msg, [id], %{state | activated: nil}}
  end
end
