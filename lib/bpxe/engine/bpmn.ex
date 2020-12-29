defmodule BPXE.Engine.BPMN do
  def add_node(node, element, attrs, body) do
    add_node(node, element, attrs)
    |> Result.map(fn ref ->
      complete_node(ref, body)
      ref
    end)
  end

  def add_node({pid, ref}, element, attrs) do
    GenServer.call(pid, {:add_node, ref, element, attrs})
  end

  def add_node(pid, element, attrs) do
    GenServer.call(pid, {:add_node, nil, element, attrs})
  end

  def complete_node(node) do
    complete_node(node, nil)
  end

  def complete_node({pid, ref}, body) do
    GenServer.call(pid, {:complete_node, ref, body})
  end

  def complete_node(pid, body) do
    GenServer.call(pid, {:complete_node, nil, body})
  end

  def add_json({pid, ref}, json) do
    GenServer.call(pid, {:add_json, ref, json})
  end

  def add_json(pid, json) do
    GenServer.call(pid, {:add_json, nil, json})
  end
end
