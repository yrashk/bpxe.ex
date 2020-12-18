defmodule BPXETest.BPMN do
  use ExUnit.Case
  doctest BPXE.BPMN

  test "parsing sample" do
    {:ok, pid} = BPXE.Engine.Instances.start_instance()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/sample.bpmn")),
        instance: pid
      )
  end
end
