defmodule BPEXE.Message do
  defstruct token: nil, content: nil, content_type: nil

  def new(options \\ []) do
    %__MODULE__{token: make_ref()}
    |> Map.merge(Map.new(options))
  end

  def combine(m1, m2) when m1.token == m2.token and m1.content_type == m2.content_type do
    %__MODULE__{
      token: m1.token,
      content: [m1.content, m2.content],
      content_type: m1.content_type
    }
  end
end
