defmodule BPXE.Helpers do
  def result(:ok), do: {:ok, nil}
  def result(:error), do: {:error, nil}
  def result({:ok, _} = ok), do: ok
  def result({:error, _} = error), do: error
  def result(value), do: {:ok, value}
end
