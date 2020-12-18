defmodule BPXE.Language.Lua do
  defstruct vm: nil

  def new() do
    {:ok, %__MODULE__{vm: :luerl_sandbox.init()}}
  end
end

defimpl BPXE.Language, for: BPXE.Language.Lua do
  def eval(%BPXE.Language.Lua{vm: vm} = instance, code) do
    try do
      {result, vm} = Luerl.do(vm, code)
      {:ok, {result, %{instance | vm: vm}}}
    rescue
      e ->
        {:error, e}
    end
  end

  def set(%BPXE.Language.Lua{vm: vm} = instance, name, variables) do
    %{instance | vm: Luerl.set_table(vm, [name], variables)}
  end

  def get(%BPXE.Language.Lua{vm: vm}, name) do
    {result, _} = Luerl.get_table(vm, [name])
    result
  end
end
