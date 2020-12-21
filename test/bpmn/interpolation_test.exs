defmodule BPXETest.BPMN.Interpolation do
  use ExUnit.Case
  doctest BPXE.BPMN.Interpolation

  describe "should return function" do
    test "that returns result as is if there's nothing else in the string but interpolation" do
      result = BPXE.BPMN.Interpolation.interpolate("${{a}}")
      assert is_function(result)
      assert result.(fn "a" -> 123 end) == 123
    end

    test "that returns result as a string if there's something else in the string beyond interpolation" do
      result = BPXE.BPMN.Interpolation.interpolate("is it ${{a}}?")
      assert is_function(result)
      assert result.(fn "a" -> 123 end) == "is it 123?"
    end
  end

  test "should use callback's optionally supplied string converter that returns string" do
    result = BPXE.BPMN.Interpolation.interpolate(~s|{"test": ${{a}}}|)
    assert is_function(result)
    assert result.(fn "a" -> {%{"a" => "b"}, &Jason.encode!/1} end) == ~s|{"test": {"a":"b"}}|
  end

  test "should use callback's optionally supplied string converter that returns a positive result" do
    result = BPXE.BPMN.Interpolation.interpolate(~s|{"test": ${{a}}}|)
    assert is_function(result)
    assert result.(fn "a" -> {%{"a" => "b"}, &Jason.encode/1} end) == ~s|{"test": {"a":"b"}}|
  end

  test "should use callback's optionally supplied string converter that returns a negative result" do
    result = BPXE.BPMN.Interpolation.interpolate(~s|{"test": ${{a}}}|)
    assert is_function(result)

    assert result.(fn "a" -> {make_ref(), &Jason.encode/1} end) =~
             "Jason.Encoder protocol must always be explicitly implemented"
  end

  test "should return string if there's no interpolation" do
    result = BPXE.BPMN.Interpolation.interpolate("just a string")
    assert result == "just a string"
  end

  test "trims strings without interpolation" do
    result =
      BPXE.BPMN.Interpolation.interpolate("""

      just a string
      """)

    assert result == "just a string"
  end

  test "trims strings with interpolation" do
    result =
      BPXE.BPMN.Interpolation.interpolate("""

      ${{a}}
      """)

    assert is_function(result)
    assert result.(fn "a" -> 123 end) == 123
  end
end
