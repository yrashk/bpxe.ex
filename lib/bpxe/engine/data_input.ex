defmodule BPXE.Engine.DataInput do
  defstruct attrs: %{}, value: nil, state: nil
  use ExConstructor

  import BPXE.Engine.BPMN

  def add_data_state(pid, attrs) do
    add_node(pid, "dataState", attrs)
  end
end
