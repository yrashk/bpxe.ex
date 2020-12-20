defmodule BPXETest.BPMN do
  use ExUnit.Case
  doctest BPXE.BPMN

  test "parsing sample" do
    {:ok, pid} = BPXE.Engine.Blueprints.start_blueprint()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/sample.bpmn")),
        blueprint: pid
      )
  end
end
