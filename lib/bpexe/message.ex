defmodule BPEXE.Message do
  defstruct message_id: nil,
            content: nil,
            __txn__: 0,
            __gen__: nil

  use ExConstructor

  def new(options \\ []) do
    result = super(options)
    %{result | message_id: result.message_id || make_ref(), __gen__: :atomics.new(2, [])}
  end

  def next_txn(%__MODULE__{__gen__: gen, __txn__: txn}) do
    case :atomics.add_get(gen, 1, 1) do
      n when n < txn ->
        :atomics.add_get(gen, 2, 1) + 18_446_744_073_709_551_615

      n ->
        n
    end
  end
end
