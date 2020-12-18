defmodule BPXE.Language.Lua do
  defstruct vm: nil

  def new() do
    {:ok, %__MODULE__{vm: :luerl_sandbox.init()}}
  end
end

defimpl BPXE.Language, for: BPXE.Language.Lua do
  def eval(%BPXE.Language.Lua{vm: vm} = instance, code) do
    try do
      {result, vm} = :luerl.do(code, vm)
      {:ok, {result, %{instance | vm: vm}}}
    rescue
      e ->
        {:error, e}
    end
  end

  def set(%BPXE.Language.Lua{vm: vm} = instance, name, variables) do
    %{instance | vm: :luerl.set_table( [name], variables, vm)}
  end

  def get(%BPXE.Language.Lua{vm: vm}, name) do
    {result, _} = :luerl.get_table([name], vm)
    result
  end
end
