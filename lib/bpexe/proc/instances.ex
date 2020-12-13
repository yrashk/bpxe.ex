defmodule BPEXE.Proc.Instances do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_instance(args) do
    DynamicSupervisor.start_child(__MODULE__, {BPEXE.Proc.Instance, [args]})
  end
end
