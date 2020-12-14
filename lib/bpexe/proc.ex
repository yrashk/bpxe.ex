defmodule BPEXE.Proc do
  alias BPEXE.BPMN.Handler, as: BPMNHandler
  @behaviour BPMNHandler

  alias BPEXE.Proc

  @impl BPMNHandler
  def new() do
    Proc.Instances.start_instance(nil)
  end

  @impl BPMNHandler
  def add_process(instance, %{"id" => id} = options) do
    id = id || make_ref()
    Proc.Instance.add_process(instance, id, options)
  end

  @impl BPMNHandler
  def add_event(process, %{"id" => id} = options, type) do
    id = id || make_ref()
    Proc.Process.add_event(process, id, options, type)
  end

  @impl BPMNHandler
  def add_signal_event_definition(event, options) do
    Proc.Event.add_signal_event_definition(event, options)
  end

  @impl BPMNHandler
  def add_task(process, %{"id" => id} = options, type \\ :task) do
    id = id || make_ref()
    Proc.Process.add_task(process, id, type, options)
  end

  @impl BPMNHandler
  def add_outgoing(node, name) do
    Proc.FlowNode.add_outgoing(node, name)
  end

  @impl BPMNHandler
  def add_incoming(node, name) do
    Proc.FlowNode.add_incoming(node, name)
  end

  @impl BPMNHandler
  def add_sequence_flow(process, %{"id" => id} = options) do
    id = id || make_ref()
    Proc.Process.add_sequence_flow(process, id, options)
  end

  @impl BPMNHandler
  def add_parallel_gateway(process, %{"id" => id} = options) do
    id = id || make_ref()
    Proc.Process.add_parallel_gateway(process, id, options)
  end

  @impl BPMNHandler
  def add_event_based_gateway(process, %{"id" => id} = options) do
    id = id || make_ref()
    Proc.Process.add_event_based_gateway(process, id, options)
  end

  @impl BPMNHandler
  def complete(instance) do
    {:ok, instance}
  end
end
