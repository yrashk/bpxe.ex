defmodule BPEXE.Language.Lua do
  defstruct vm: nil

  def new() do
    {:ok, %__MODULE__{vm: :luerl_sandbox.init()}}
  end
end

defimpl BPEXE.Language, for: BPEXE.Language.Lua do
  def eval(%BPEXE.Language.Lua{vm: vm} = instance, code) do
    try do
      {result, vm} = Luerl.do(vm, code)
      {:ok, {result, %{instance | vm: vm}}}
    rescue
      e ->
        e
        {:error, e}
    end
  end

  def set(%BPEXE.Language.Lua{vm: vm} = instance, name, variables) do
    %{instance | vm: Luerl.set_table(vm, [name], variables)}
  end

  def get(%BPEXE.Language.Lua{vm: vm} = instance, name) do
    {result, _} = Luerl.get_table(vm, [name])
    result
  end
end
