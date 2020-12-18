defmodule BPEXETest.Message do
  use ExUnit.Case
  doctest BPEXE.Message

  test "generating new transaction ID always generates non-duplicate, monotonic IDs" do
    message = BPEXE.Message.new()

    pid = self()

    for _ <- 1..1000 do
      spawn_link(fn -> send(pid, BPEXE.Message.next_txn(message)) end)
    end

    messages = receive_all(1000) |> Enum.uniq() |> Enum.sort()

    assert length(messages) == 1000
    assert 1..1000 |> Enum.to_list() == messages
  end

  test "generating more than 2^64 IDs still works (even though this is unlikely)" do
    message = BPEXE.Message.new()
    :atomics.add(message.__gen__, 1, 18_446_744_073_709_551_615)

    assert BPEXE.Message.next_txn(%{message | __txn__: 18_446_744_073_709_551_615}) ==
             18_446_744_073_709_551_616
  end

  defp receive_all(0), do: []

  defp receive_all(n) do
    receive do
      message -> [message | receive_all(n - 1)]
    end
  end
end
