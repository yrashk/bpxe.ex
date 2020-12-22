defmodule BPXE.Token do
  defstruct token_id: nil,
            payload: %{},
            __generation__: 0

  use ExConstructor
  alias BPXE.Engine.Process.Activation

  def new(options \\ []) do
    result = super(options)

    %{
      result
      | __generation__: {options[:activation] || 0, 0},
        token_id: result.token_id || generate_id()
    }
  end

  def next_generation(%__MODULE__{
        __generation__: {activation, _}
      }) do
    {activation, Activation.next_token_generation(activation)}
  end

  @doc """
  Distance between generations of two tokens. Returns `nil` if they are not
  in the same activation (comparing them is useless), otherwise it's a number
  of single incremenets from the first token to the second one (positive means
  the second message is younger, negative is older, zero is it's the same generation)
  """
  def distance(
        %__MODULE__{__generation__: {a, g1}} = _first,
        %__MODULE__{__generation__: {a, g2}} = _second
      ) do
    g2 - g1
  end

  def later_than(_, _), do: nil

  defp generate_id() do
    {m, f, a} = Application.get_env(:bpxe, :token_id_generator)
    apply(m, f, a)
  end

  def generation(%__MODULE__{__generation__: {_, generation}}), do: generation
  def activation(%__MODULE__{__generation__: {activation, _}}), do: activation

  @doc ~S"""
  Merges two tokens

  ## Examples

    iex> BPXE.Token.merge(BPXE.Token.new(token_id: 1, payload: %{"a" => 1, "b" => %{"c" => 2}}),
    iex>                  BPXE.Token.new(token_id: 1, payload: %{"a" => 2, "b" => %{"d" => 4}})).payload
    %{"a" => 2, "b" => %{"c" => 2, "d" => 4}}

  """
  def merge(%__MODULE__{token_id: id, payload: payload1} = t1, %__MODULE__{
        token_id: id,
        payload: payload2
      }) do
    %{t1 | payload: DeepMerge.deep_merge(payload1, payload2)}
  end
end
