defmodule BPXE.Message do
  defstruct message_id: nil,
            content: nil,
            __generation__: 0,
            __generation_atomic__: nil

  use ExConstructor

  def new(options \\ []) do
    result = super(options)

    %{
      result
      | __generation__: {options[:activation] || 0, 0},
        message_id: result.message_id || generate_id(),
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
    {m, f, a} = Application.get_env(:bpxe, :message_id_generator)
    apply(m, f, a)
  end

  def generation(%__MODULE__{__generation__: {_, generation}}), do: generation
  def activation(%__MODULE__{__generation__: {activation, _}}), do: activation
end
