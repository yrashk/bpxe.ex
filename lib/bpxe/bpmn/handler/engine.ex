defmodule BPXE.BPMN.Handler.Engine do
  alias BPXE.BPMN.Handler, as: BPMNHandler
  @behaviour BPMNHandler

  alias BPXE.Engine

  @impl BPMNHandler
  def add_process(model, %{"id" => id} = options) do
    id = id || generate_id()
    Engine.Model.add_process(model, id, options)
  end

  @impl BPMNHandler
  def add_event(process, type, %{"id" => id} = options) do
    id = id || generate_id()
    Engine.Process.add_event(process, id, type, options)
  end

  @impl BPMNHandler
  def add_signal_event_definition(event, options) do
    Engine.Event.add_signal_event_definition(event, options)
  end

  @impl BPMNHandler
  def add_task(process, %{"id" => id} = options, type \\ :task) do
    id = id || generate_id()
    Engine.Process.add_task(process, id, type, options)
  end

  @impl BPMNHandler
  def add_script(task, text) do
    Engine.Task.add_script(task, text)
  end

  @impl BPMNHandler
  def add_outgoing(node, name) do
    Engine.FlowNode.add_outgoing(node, name)
  end

  @impl BPMNHandler
  def add_incoming(node, name) do
    Engine.FlowNode.add_incoming(node, name)
  end

  @impl BPMNHandler
  def add_sequence_flow(process, %{"id" => id} = options) do
    id = id || generate_id()
    Engine.Process.add_sequence_flow(process, id, options)
  end

  @impl BPMNHandler
  def add_condition_expression(node, options, body) do
    Engine.FlowNode.add_condition_expression(node, options, body)
  end

  @impl BPMNHandler
  def add_parallel_gateway(process, %{"id" => id} = options) do
    id = id || generate_id()
    Engine.Process.add_parallel_gateway(process, id, options)
  end

  @impl BPMNHandler
  def add_inclusive_gateway(process, %{"id" => id} = options) do
    id = id || generate_id()
    Engine.Process.add_inclusive_gateway(process, id, options)
  end

  @impl BPMNHandler
  def add_event_based_gateway(process, %{"id" => id} = options) do
    id = id || generate_id()
    Engine.Process.add_event_based_gateway(process, id, options)
  end

  @impl BPMNHandler
  def add_extension_elements(node) do
    Engine.Base.add_extension_elements(node)
  end

  @impl BPMNHandler
  def add_json(node, json) do
    Engine.Base.add_json(node, json)
  end

  @impl BPMNHandler
  def complete(model) do
    {:ok, model}
  end

  defp generate_id() do
    {m, f, a} = Application.get_env(:bpxe, :spec_id_generator)
    apply(m, f, a)
  end
end
