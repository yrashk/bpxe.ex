defmodule BPEXE.Language.Lua do
  defstruct vm: nil

  def new() do
    {:ok, %__MODULE__{vm: :lua_sandbox.init()}}
  end
end

defimpl BPEXE.Language, for: BPEXE.Language.Lua do
  def eval(%BPEXE.Language.Lua{vm: vm} = instance, code) do
    Lua.do(vm, code)
    |> Result.map(fn {value, vm} -> {value, %{instance | vm: vm}} end)
  end
end
