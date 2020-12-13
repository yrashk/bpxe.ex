defmodule BPEXE.Proc.Task do
  use GenServer
  use BPEXE.Proc.FlowNode

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
    {:ok, vm} = BPMN.Language.Lua.new()
    {:send, msg, state}
  end

  def handle_message({msg, _id}, state) do
  end
end
