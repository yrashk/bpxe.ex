defmodule BPXETest.BPMN.JSON do
  use ExUnit.Case, async: true
  doctest BPXE.BPMN.JSON
  alias BPXE.Engine.{Model, Models}

  @json [
    %{"test" => 123, "world" => "hello", "again" => %{"yes" => 321}},
    ["123", 123],
    123,
    123.123,
    true,
    nil
  ]

  test "should parse JSON XML extension" do
    {:ok, pid} = Models.start_model()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/json_xml.bpmn")),
        model: pid
      )

    assert @json == jsons(pid)
  end

  test "should parse plain JSON extension" do
    {:ok, pid} = Models.start_model()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/json.bpmn")),
        model: pid
      )

    assert @json == jsons(pid)
  end

  defp jsons(pid) do
    model = Model.model(pid)
    Warpath.query!(model, "$.process.serviceTask.extensionElements.:json[*].:body")
  end
end
