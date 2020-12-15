defmodule BPEXE.Message do
  defstruct token: nil, content: nil, __invisible__: false
  use ExConstructor

  def new(options \\ []) do
    result = super(options)
    %{result | token: result.token || make_ref()}
  end
end
