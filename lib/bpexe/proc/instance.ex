defmodule BPEXE.Proc.Instance do
  use GenServer

  defstruct args: %{}, processes: %{}

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def add_process(pid, id, options) do
    GenServer.call(pid, {:add_process, id, options})
  end

  def processes(pid) do
    GenServer.call(pid, :processes)
  end

  def start(pid) do
    processes = processes(pid)

    if Enum.empty?(processes) do
      {:error, :no_processes}
    else
      Enum.map(processes, fn id ->
        {id, start(pid, id)}
      end)
    end
  end

  def start(pid, process_id) do
    process = :syn.whereis({pid, :process, process_id})
    BPEXE.Proc.Process.start(process)
  end

  def init(args) do
    {:ok, %__MODULE__{args: args}}
  end

  def handle_call({:add_process, id, options}, _from, state) do
    case BPEXE.Proc.Process.start_link(id, options, self()) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, %{state | processes: Map.put(state.processes, id, options)}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:processes, _from, state) do
    {:reply, Map.keys(state.processes), state}
  end
end
