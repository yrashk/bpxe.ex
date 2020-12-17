defmodule BPEXETest.BPMN do
  use ExUnit.Case
  doctest BPEXE.BPMN

  test "parsing sample" do
    {:ok, pid} = BPEXE.Engine.Instances.start_instance()

    {:ok, _} =
      BPEXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/sample.bpmn")),
        instance: pid
      )
  end
end
