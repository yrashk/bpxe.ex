defmodule BPXETest.BPMN do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Blueprint
  alias BPXE.Engine.Blueprint.Recordable.Ref
  doctest BPXE.BPMN
  import BPXETest.Utils

  test "parsing sample" do
    {:ok, pid} = BPXE.Engine.Blueprints.start_blueprint()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/sample.bpmn")),
        blueprint: pid
      )
  end

  test "should interpolate expressions in bpxe:json and output results as JSON" do
    {:ok, pid} = BPXE.Engine.Blueprints.start_blueprint()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/interpolation.bpmn")),
        blueprint: pid
      )

    blueprint = Blueprint.blueprint(pid)

    %Ref{payload: {:add_json, _, expr}} =
      find_blueprint(blueprint, ["sample", "start", :add_extension_elements, :add_json])

    assert is_function(expr)

    assert expr.(fn "test" -> %{"b" => "c"} end) == {:ok, %{"a" => %{"b" => "c"}}}
  end

  test "should interpolate expressions in XSL JSON and output results as strings (only primitive types allowed)" do
    {:ok, pid} = BPXE.Engine.Blueprints.start_blueprint()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/interpolation.bpmn")),
        blueprint: pid
      )

    blueprint = Blueprint.blueprint(pid)

    %Ref{payload: {:add_json, _, expr}} =
      find_blueprint(blueprint, ["sample", "end", :add_extension_elements, :add_json])

    assert is_function(expr)

    assert expr.(fn
             "a" -> 3
             "b" -> true
           end) == %{"test" => 3, "hello" => "3", "hey" => true}
  end
end
