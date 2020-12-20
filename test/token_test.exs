defmodule BPXETest.Token do
  use ExUnit.Case
  doctest BPXE.Token

  test "generating new generation ID always generates non-duplicate, monotonic IDs" do
    token = BPXE.Token.new()

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
  end

  test "generating more than 2^64 IDs still works (even though this is unlikely)" do
    token = BPXE.Token.new()
    :atomics.add(token.__generation_atomic__, 1, 18_446_744_073_709_551_615)

    assert BPXE.Token.next_generation(%{
             token
             | __generation__: {0, 18_446_744_073_709_551_615}
           }) ==
             {0, 18_446_744_073_709_551_616}
  end

  defp receive_all(0), do: []

  defp receive_all(n) do
    receive do
      token -> [token | receive_all(n - 1)]
    end
  end
end
