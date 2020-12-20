defmodule BPXETest.BPMN.JSON do
  use ExUnit.Case
  doctest BPXE.BPMN.JSON
  alias BPXE.Engine.{Blueprint, Blueprints}

  @json [
    %{"test" => 123, "world" => "hello", "again" => %{"yes" => 321}},
    ["123", 123],
    123,
    123.123,
    true,
    nil
  ]

  test "should parse JSON XML extension" do
    {:ok, pid} = Blueprints.start_blueprint()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/json_xml.bpmn")),
        blueprint: pid
      )

    assert @json == jsons(pid)
  end

  test "should parse plain JSON extension" do
    {:ok, pid} = Blueprints.start_blueprint()

    {:ok, _} =
      BPXE.BPMN.parse_stream(File.stream!(Path.join(__DIR__, "/files/json.bpmn")),
        blueprint: pid
      )

    assert @json == jsons(pid)
  end

  defp jsons(pid) do
    alias BPXE.Engine.Blueprint.Recordable.Ref
    blueprint = Blueprint.blueprint(pid)

    process =
      Enum.find_value(blueprint, fn {nil, records} ->
        Enum.find_value(records, fn
          %Ref{payload: {:add_process, "process", _}} = ref ->
            ref

          _ ->
            false
        end)
      end)

    task =
      Enum.find_value(blueprint[process], fn
        %Ref{payload: {:add_task, "task", _, _}} = ref ->
          ref

        _ ->
          false
      end)

    extension_elements =
      Enum.find_value(blueprint[task], fn
        %Ref{payload: :add_extension_elements} = ref ->
          ref

        _ ->
          false
      end)

    Enum.filter(blueprint[extension_elements], fn
      %Ref{payload: {:add_json, nil, _}} = ref ->
        ref

      _ ->
        false
    end)
    |> Enum.map(fn %Ref{payload: {:add_json, nil, json}} -> json end)
  end
end
