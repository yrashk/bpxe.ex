defmodule BPEXETest.Proc.Instance do
  use ExUnit.Case
  alias BPEXE.Proc.Instance
  doctest Instance

  test "starting instance" do
    {:ok, _pid} = Instance.start_link(:ignored)
  end

  test "adding processes and listing them" do
    {:ok, pid} = Instance.start_link(:ignored)
    {:ok, _} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})
    {:ok, _} = Instance.add_process(pid, "proc2", %{"id" => "proc2", "name" => "Proc 2"})
    assert Instance.processes(pid) |> Enum.sort() == ["proc1", "proc2"] |> Enum.sort()
  end
end
