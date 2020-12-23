defmodule BPXETest.Token do
  use ExUnit.Case, async: true
  doctest BPXE.Token

  test "generating new generation ID always generates non-duplicate, monotonic IDs" do
    activation = BPXE.Engine.Process.Activation.new()
    token = BPXE.Token.new(activation: activation)

    pid = self()

    for _ <- 1..1000 do
      spawn_link(fn ->
        {_activation, id} = BPXE.Token.next_generation(token)
        send(pid, id)
      end)
    end

    tokens = receive_all(1000) |> Enum.uniq() |> Enum.sort()

    assert length(tokens) == 1000
    assert 1..1000 |> Enum.to_list() == tokens

    BPXE.Engine.Process.Activation.discard(activation)
  end

  defp receive_all(0), do: []

  defp receive_all(n) do
    receive do
      token -> [token | receive_all(n - 1)]
    end
  end
end
