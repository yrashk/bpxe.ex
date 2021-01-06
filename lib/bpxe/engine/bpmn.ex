defmodule BPXE.Engine.BPMN do
  def add_node(node, element, attrs, body) do
    add_node(node, element, attrs)
    |> Result.map(fn ref ->
      complete_node(ref, body)
      ref
    end)
  end

  def add_node(pid, element, body) when is_binary(body) do
    add_node(pid, element, %{}, body)
  end

  def add_node({pid, ref}, element, attrs) do
    attrs = Enum.map(attrs, &process_attribute/1) |> Map.new()
    attrs = update_in(attrs["id"], &(&1 || generate_id()))
    GenServer.call(pid, {:add_node, ref, element, attrs})
  end

  def add_node(pid, element, attrs) do
    add_node({pid, nil}, element, attrs)
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

  defp generate_id() do
    {m, f, a} = Application.get_env(:bpxe, :spec_id_generator)
    apply(m, f, a)
  end

  for {key, _} <- BPXE.BPMN.Semantic.core_attributes() do
    @key String.to_atom(key)
    @stringified_key key
    defp process_attribute({@key, value}), do: {@stringified_key, value |> to_string()}
  end

  for {key, _} <- BPXE.BPMN.Semantic.extension_attributes() do
    @key String.to_atom(key)
    @stringified_key key
    defp process_attribute({{ns, @key}, value}),
      do: {{ns, @stringified_key}, value |> to_string()}
  end

  defp process_attribute({key, value}), do: {key, value}
end
