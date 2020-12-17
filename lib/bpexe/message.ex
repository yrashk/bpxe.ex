defmodule BPEXE.Message do
  defstruct token: nil,
            content: nil,
            __txn__: 0,
            __gen__: nil

  use ExConstructor

  def new(options \\ []) do
    result = super(options)
    %{result | token: result.token || make_ref(), __gen__: :atomics.new(1, [])}
  end

  def next_txn(%__MODULE__{__gen__: gen}) do
    case :atomics.add_get(gen, 1, 1) do
      0 ->
        # FIXME: we wrapped, what should we do? use the next number in the array and sum them?
        0

      n ->
        n
    end
  end
end
