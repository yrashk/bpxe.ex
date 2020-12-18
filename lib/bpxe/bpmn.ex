defmodule BPXE.BPMN do
  def ext_spec() do
    "http://bpxe.org/spec/current"
  end

  def parse(string, options \\ []) when is_binary(string) do
    Saxy.parse_string(string, BPXE.BPMN.Handler, options)
  end

  def parse_stream(stream, options \\ []) do
    Saxy.parse_stream(stream, BPXE.BPMN.Handler, options)
  end
end
