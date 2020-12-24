defmodule BPXETest.BPMN.JSON do
  use ExUnit.Case, async: true
  doctest BPXE.BPMN.JSON
  alias BPXE.Engine.{Model, Models}
  import BPXETest.Utils

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
    alias BPXE.Engine.Model.Recordable.Ref
    model = Model.model(pid)

    extension_elements = find_model(model, ["process", "task", :add_extension_elements])

    Enum.filter(model[extension_elements], fn
      %Ref{payload: {:add_json, nil, _}} = ref ->
        ref

      _ ->
        false
    end)
    |> Enum.map(fn %Ref{payload: {:add_json, nil, json}} -> json end)
  end
end
