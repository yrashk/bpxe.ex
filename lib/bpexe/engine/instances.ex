defmodule BPEXE.Engine.Instances do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_instance(options \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {BPEXE.Engine.Instance, options})
  end

  def stop_instance(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
