defmodule BPEXETest.Engine.Instance do
  use ExUnit.Case
  alias BPEXE.Engine.Instance
  alias BPEXE.Engine.Process
  doctest Instance

  test "starting instance" do
    {:ok, _pid} = Instance.start_link()
  end

  test "adding processes and listing them" do
    {:ok, pid} = Instance.start_link()
    {:ok, _} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})
    {:ok, _} = Instance.add_process(pid, "proc2", %{"id" => "proc2", "name" => "Proc 2"})

    assert Instance.processes(pid) |> Enum.sort() == ["proc1", "proc2"] |> Enum.sort()
  end

  test "starting an instance with no processes" do
    {:ok, pid} = Instance.start_link()
    assert {:error, :no_processes} == Instance.start(pid)
  end

  test "starting an instance with one process that has no start events" do
    {:ok, pid} = Instance.start_link()
    {:ok, _} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, proc2} = Instance.add_process(pid, "proc2", %{"id" => "proc2", "name" => "Proc 2"})

    {:ok, _} = Process.add_event(proc2, "start", %{"id" => "start"}, :startEvent)

    assert [{"proc1", {:error, :no_start_events}}, {"proc2", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)
  end
end
