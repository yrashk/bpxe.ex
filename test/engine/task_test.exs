defmodule BPEXETest.Engine.Task do
  use ExUnit.Case
  alias BPEXE.Engine.Instance
  alias BPEXE.Engine.{Process, Task}
  alias BPEXE.Engine.Process.Log
  doctest Instance

  test "executes a script, captures state and retrieves it in other scripts" do
    {:ok, pid} = Instance.start_link()
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", %{"id" => "start"}, :startEvent)
    {:ok, task} = Process.add_task(proc1, "task", :scriptTask, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, ~s|
      process.a = {}
      process.a.v = 1
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)

    {:ok, task2} = Process.add_task(proc1, "task2", :scriptTask, %{"id" => "task2"})
    {:ok, _} = Task.add_script(task2, ~s|
      process.a.v = process.a.v + 2
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, task2)

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.TaskCompleted{id: "task"}})
    assert_receive({Log, %Log.TaskCompleted{id: "task2"}})
    assert Process.variables(proc1) == %{"a" => %{"v" => 3}}
  end

  test "executes a script that modifies no state" do
    {:ok, pid} = Instance.start_link()
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", %{"id" => "start"}, :startEvent)
    {:ok, task} = Process.add_task(proc1, "task", :scriptTask, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, ~s|
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.TaskCompleted{id: "task"}})
    assert Process.variables(proc1) == %{}
  end
end
