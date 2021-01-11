defmodule BPXE.Engine.DataObjectReference do
  defstruct attrs: %{}, state: nil
  use ExConstructor

  import BPXE.Engine.BPMN

  def add_data_state(pid, attrs) do
    add_node(pid, "dataState", attrs)
  end
end
