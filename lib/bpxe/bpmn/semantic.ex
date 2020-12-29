defmodule BPXE.BPMN.Semantic do
  alias BPXE.BPMN.Semantic.Handler

  {:ok, semantic} =
    Saxy.parse_stream(
      File.stream!(Path.join([__DIR__, "..", "..", "..", "priv", "schemas", "Semantic.xsd"])),
      Handler,
      %Handler{}
    )

  {:ok, semantic_extensions} =
    Saxy.parse_stream(
      File.stream!(Path.join([__DIR__, "..", "..", "..", "priv", "schemas", "bpxe.xsd"])),
      Handler,
      %Handler{exclude: ~w(json)}
    )

  @semantic semantic
  @semantic_extensions semantic_extensions
  @elements Map.merge(semantic.elements, semantic_extensions.elements)

  def elements() do
    @elements
  end

  def core_elements() do
    @semantic.elements
  end

  def extension_elements() do
    @semantic_extensions.elements
  end
end
