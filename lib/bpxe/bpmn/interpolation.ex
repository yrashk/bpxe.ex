defmodule BPXE.BPMN.Interpolation do
  @moduledoc """
  This is a generalized approach to interpolation in BPXE/BPMN, allowing to pass runtime-derived values into content
  and attributes of various nodes.

  The interpolation syntax is simple: anything enclosed between `${{` and `}}` will be considered an expression. Currently,
  there is no escaping. If the entire string is one interpolation, the type of the expression will be preserved. Otherwise,
  it'll be encoded into a string.

  """

  @doc """
  Interpolates a string if it has any interpolations in it. 

  If it does, it returns a function that takes
  one argument, which is a callback that resolves the value of the given expression.

  If it doesn't, it'll return a string as is.
  """
  def interpolate(string) when is_binary(string) do
    string = string |> String.trim()

    if String.contains?(string, "${{") do
      fn cb -> interpolate(string |> String.to_charlist(), [], cb) end
    else
      string
    end
  end

  defp interpolate([?$, ?{, ?{ | rest], acc, cb) do
    {expr, rest} = expression(rest, [])

    evaluated = cb.(expr)

    {evaluated, to_string_f} =
      case evaluated do
        {s, f} when is_function(f, 1) -> {s, f}
        s -> {s, &to_string/1}
      end

    case {evaluated, to_string_f} do
      {result, _} when length(acc) == 0 and length(rest) == 0 ->
        result

      {result, f} ->
        case f.(result) do
          {:ok, result} ->
            interpolate(rest, [result | acc], cb)

          {:error, reason} ->
            interpolate(rest, ["(error: #{inspect(reason)})" | acc], cb)

          result ->
            interpolate(rest, [result | acc], cb)
        end
    end
  end

  defp interpolate([c | rest], acc, cb) do
    interpolate(rest, [c | acc], cb)
  end

  defp interpolate([], acc, _cb) do
    acc |> Enum.reverse() |> :erlang.iolist_to_binary()
  end

  defp expression([?}, ?} | rest], collected) do
    {collected |> Enum.reverse() |> :erlang.iolist_to_binary(), rest}
  end

  defp expression([c | rest], collected) do
    expression(rest, [c | collected])
  end
end
