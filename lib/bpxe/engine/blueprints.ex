defmodule BPXE.Engine.Blueprints do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_blueprint(options \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {BPXE.Engine.Blueprint, options})
  end

  def stop_blueprint(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
