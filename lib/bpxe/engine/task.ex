defmodule BPXE.Engine.Task do
  use GenServer
  use BPXE.Engine.FlowNode
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log

  defstate([id: nil, type: nil, options: %{}, instance: nil, process: nil, script: ""],
    persist: []
  )

  def start_link(id, type, options, instance, process) do
    start_link([{id, type, options, instance, process}])
  end

  def add_script(pid, script) do
    GenServer.call(pid, {:add_script, script})
  end

  def init({id, type, options, instance, process}) do
    state = %__MODULE__{
      id: id,
      type: type,
      options: options,
      instance: instance,
      process: process
    }

    state = initialize(state)
    init_ack()
    enter_loop(state)
  end

  @process_var "process"

  def handle_message({msg, _id}, %__MODULE__{type: :scriptTask} = state) do
    Process.log(state.process, %Log.TaskActivated{
      pid: self(),
      id: state.id,
      message_id: msg.message_id
    })

    {:ok, vm} = BPXE.Language.Lua.new()
    state0 = Process.variables(state.process)
    vm = BPXE.Language.set(vm, @process_var, state0)
    # TODO: handle errors
    {:ok, {_result, vm}} = BPXE.Language.eval(vm, state.script)
    state1 = BPXE.Language.get(vm, @process_var) |> ensure_maps()

    Process.set_variables(state.process, updated_state(state0, state1))

    Process.log(state.process, %Log.TaskCompleted{
      pid: self(),
      id: state.id,
      message_id: msg.message_id
    })

    {:send, msg, state}
  end

  def handle_message({msg, _id}, state) do
    Process.log(state.process, %Log.TaskActivated{
      pid: self(),
      id: state.id,
      message_id: msg.message_id
    })

    Process.log(state.process, %Log.TaskCompleted{
      pid: self(),
      id: state.id,
      message_id: msg.message_id
    })

    {:send, msg, state}
  end

  def handle_call({:add_script, script}, _from, state) do
    {:reply, {:ok, script}, %{state | script: script}}
  end

  defp ensure_maps(m) when is_map(m), do: m

  defp ensure_maps([{key, value} | rest]) do
    [{key, ensure_maps(value)} | ensure_maps_(rest)] |> Map.new()
  end

  defp ensure_maps([]), do: %{}
  defp ensure_maps(other), do: other
  # handles end of list
  defp ensure_maps_([]), do: []
  defp ensure_maps_(other), do: ensure_maps(other)

  defp updated_state(state0, state1) do
    case MapDiff.diff(state0, state1) do
      %{added: added} -> added
      _ -> %{}
    end
  end
end
