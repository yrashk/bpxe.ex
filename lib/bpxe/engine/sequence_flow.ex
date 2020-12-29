defmodule BPXE.Engine.SequenceFlow do
  import BPXE.Engine.BPMN

  def add_condition_expression(pid, attrs, body \\ nil) do
    add_node(pid, "conditionExpression", attrs, body)
  end
end
