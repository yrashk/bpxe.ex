defmodule BPXE.Engine.Models do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_model(options \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {BPXE.Engine.Model, options})
  end

  def stop_model(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
