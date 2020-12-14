defmodule BPEXE.Proc.Task do
  use GenServer
  use BPEXE.Proc.Base
  use BPEXE.Proc.FlowNode
  alias BPEXE.Proc.Process
  alias BPEXE.Proc.Process.Log

  defstruct id: nil,
            type: nil,
            options: %{},
            instance: nil,
            process: nil,
            outgoing: [],
            incoming: []

  def start_link(id, type, options, instance, process) do
    GenServer.start_link(__MODULE__, {id, type, options, instance, process})
  end

  def init({id, type, options, instance, process}) do
    {:ok, %__MODULE__{id: id, type: type, options: options, instance: instance, process: process}}
  end

  def handle_message({msg, _id}, %__MODULE__{type: :scriptTask, options: options} = state) do
    Process.log(state.process, %Log.TaskActivated{pid: self(), id: state.id, token: msg.token})
    {:ok, vm} = BPMN.Language.Lua.new()
    Process.log(state.process, %Log.TaskCompleted{pid: self(), id: state.id, token: msg.token})
    {:send, msg, state}
  end

  def handle_message({msg, _id}, state) do
    Process.log(state.process, %Log.TaskActivated{pid: self(), id: state.id, token: msg.token})
    Process.log(state.process, %Log.TaskCompleted{pid: self(), id: state.id, token: msg.token})
    {:send, msg, state}
  end
end
