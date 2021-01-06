defmodule BPXE.BPMN.Semantic.Handler do
  @behaviour Saxy.Handler
  defstruct elements: %{}, attributes: %{}, exclude: []

  def handle_event(:start_document, _prolog, state) do
    {:ok, state}
  end

  def handle_event(:end_document, _data, state) do
    {:ok, state}
  end

  def handle_event(:start_element, {"xsd:element", attrs}, state) do
    attrs = Map.new(attrs)

    unless attrs["name"] in state.exclude do
      {:ok, put_in(state.elements[attrs["name"]], attrs)}
    else
      {:ok, state}
    end
  end

  def handle_event(:start_element, {"xsd:attribute", attrs}, state) do
    attrs = Map.new(attrs)

    unless attrs["name"] in state.exclude do
      {:ok, put_in(state.attributes[attrs["name"]], attrs)}
    else
      {:ok, state}
    end
  end

  def handle_event(_, _, state) do
    {:ok, state}
  end
end
