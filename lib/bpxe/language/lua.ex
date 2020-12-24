defmodule BPXE.Language.Lua do
  defstruct vm: nil

  def new() do
    {:ok, %__MODULE__{vm: :luerl_sandbox.init()}}
  end
end

defimpl BPXE.Language, for: BPXE.Language.Lua do
  def eval(%BPXE.Language.Lua{vm: vm} = model, code) do
    try do
      {result, vm} = :luerl.do(code, vm)
      {:ok, {result, %{model | vm: vm}}}
    rescue
      e ->
        {:error, e}
    end
  end

  def set(%BPXE.Language.Lua{vm: vm} = model, name, variables) do
    %{model | vm: :luerl.set_table([name], variables, vm)}
  end

  def get(%BPXE.Language.Lua{vm: vm}, name) do
    {result, _} = :luerl.get_table([name], vm)
    result |> ensure_maps()
  end

  defp ensure_maps([{key, value}]) do
    %{key => ensure_maps(value)}
  end

  defp ensure_maps([{key, value} | rest]) do
    Map.merge(ensure_maps(rest), %{key => ensure_maps(value)})
  end

  defp ensure_maps(v), do: v
end
