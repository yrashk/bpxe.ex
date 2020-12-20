defmodule BPXE.Token do
  defstruct token_id: nil,
            payload: %{},
            __generation__: 0,
            __generation_atomic__: nil

  use ExConstructor

  def new(options \\ []) do
    result = super(options)

    %{
      result
      | __generation__: {options[:activation] || 0, 0},
        token_id: result.token_id || generate_id(),
        __generation_atomic__: :atomics.new(2, [])
    }
  end

  def next_generation(%__MODULE__{
        __generation_atomic__: gen,
        __generation__: {activation, generation}
      }) do
    {activation,
     case :atomics.add_get(gen, 1, 1) do
       n when n < generation ->
         :atomics.add_get(gen, 2, 1) + 18_446_744_073_709_551_615

       n ->
         n
     end}
  end

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
