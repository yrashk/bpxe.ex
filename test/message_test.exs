defmodule BPXETest.Message do
  use ExUnit.Case
  doctest BPXE.Message

  test "generating new generation ID always generates non-duplicate, monotonic IDs" do
    message = BPXE.Message.new()

    pid = self()

    for _ <- 1..1000 do
      spawn_link(fn ->
        {_activation, id} = BPXE.Message.next_generation(message)
        send(pid, id)
      end)
    end

    messages = receive_all(1000) |> Enum.uniq() |> Enum.sort()

    assert length(messages) == 1000
    assert 1..1000 |> Enum.to_list() == messages
  end

  test "generating more than 2^64 IDs still works (even though this is unlikely)" do
    message = BPXE.Message.new()
    :atomics.add(message.__generation_atomic__, 1, 18_446_744_073_709_551_615)

    assert BPXE.Message.next_generation(%{
             message
             | __generation__: {0, 18_446_744_073_709_551_615}
           }) ==
             {0, 18_446_744_073_709_551_616}
  end

  defp receive_all(0), do: []

  defp receive_all(n) do
    receive do
      message -> [message | receive_all(n - 1)]
    end
  end
end
