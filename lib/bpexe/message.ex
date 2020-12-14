defmodule BPEXE.Message do
  defstruct token: nil, content: nil, content_type: nil

  def new(options \\ []) do
    %__MODULE__{token: make_ref()}
    |> Map.merge(Map.new(options))
  end
end
