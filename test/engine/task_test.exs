defmodule BPXETest.Engine.Task do
  use ExUnit.Case
  alias BPXE.Engine.Blueprint
  alias BPXE.Engine.{Process, Task, Base}
  alias BPXE.Engine.Process.Log
  doctest Task

  test "executes a script, captures state and retrieves it in other scripts" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
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

    {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.TaskCompleted{id: "task"}})
    assert_receive({Log, %Log.TaskCompleted{id: "task2"}})
    assert Base.variables(proc1) == %{"a" => %{"v" => 3}}
  end

  test "executes a script that modifies no state" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, task} = Process.add_task(proc1, "task", :scriptTask, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, ~s|
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)

    {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.TaskCompleted{id: "task"}})
    assert Base.variables(proc1) == %{}
  end
end
