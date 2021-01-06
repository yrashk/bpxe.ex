defmodule BPXETest.Engine.Activity do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Model
  alias BPXE.Engine.{Activity, Process, Task, Base}
  alias BPXE.Engine.Process.Log
  doctest Task

  @xsi "http://www.w3.org/2001/XMLSchema-instance"

  describe "standard loop" do
    test "should run while condition satisfies with testBefore implied to be false" do
      {:ok, pid} = Model.start_link()
      {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

      {:ok, start} = Process.add_start_event(proc1, id: "start")
      {:ok, the_end} = Process.add_end_event(proc1, id: "end")
      {:ok, task} = Process.add_script_task(proc1, id: "task")
      {:ok, _} = Task.add_script(task, %{}, ~s|
        process.a = (process.a or 0) + 1
        flow.a = (flow.a or 0) + 1
      |)

      {:ok, loop} = Activity.add_standard_loop_characteristics(task, id: "loop")

      {:ok, _} =
        Activity.add_loop_condition(
          loop,
          %{{@xsi, "type"} => "tFormalExpression"},
          "loopCounter < `4`"
        )

      {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
      {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

      {:ok, proc1} = Model.provision_process(pid, "proc1")
      :ok = Process.subscribe_log(proc1)

      initial_vars = Base.variables(proc1)

      assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
               Model.start(pid) |> List.keysort(0)

      assert_receive({Log, %Log.FlowNodeForward{id: "task"}})
      assert Base.variables(proc1) == Map.merge(initial_vars, %{"a" => 4})

      assert_receive(
        {Log, %Log.FlowNodeActivated{id: "end", token: %BPXE.Token{payload: %{"a" => var_a}}}}
      )

      assert var_a == 4
    end

    test "should run while condition satisfies with testBefore set to true" do
      {:ok, pid} = Model.start_link()
      {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

      {:ok, start} = Process.add_start_event(proc1, id: "start")
      {:ok, the_end} = Process.add_end_event(proc1, id: "end")
      {:ok, task} = Process.add_script_task(proc1, id: "task")
      {:ok, _} = Task.add_script(task, %{}, ~s|
        process.a = (process.a or 0) + 1
        flow.a = (flow.a or 0) + 1
      |)

      {:ok, loop} = Activity.add_standard_loop_characteristics(task, id: "loop", testBefore: true)

      {:ok, _} =
        Activity.add_loop_condition(
          loop,
          %{{@xsi, "type"} => "tFormalExpression"},
          "loopCounter < `4`"
        )

      {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
      {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

      {:ok, proc1} = Model.provision_process(pid, "proc1")
      :ok = Process.subscribe_log(proc1)

      initial_vars = Base.variables(proc1)

      assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
               Model.start(pid) |> List.keysort(0)

      assert_receive({Log, %Log.FlowNodeForward{id: "task"}})
      assert Base.variables(proc1) == Map.merge(initial_vars, %{"a" => 3})

      assert_receive(
        {Log, %Log.FlowNodeActivated{id: "end", token: %BPXE.Token{payload: %{"a" => var_a}}}}
      )

      assert var_a == 3
    end

    test "should respect loop cap specified in loopMaximum" do
      {:ok, pid} = Model.start_link()
      {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

      {:ok, start} = Process.add_start_event(proc1, id: "start")
      {:ok, the_end} = Process.add_end_event(proc1, id: "end")
      {:ok, task} = Process.add_script_task(proc1, id: "task")
      {:ok, _} = Task.add_script(task, %{}, ~s|
        process.a = (process.a or 0) + 1
        flow.a = (flow.a or 0) + 1
      |)

      {:ok, loop} =
        Activity.add_standard_loop_characteristics(task,
          id: "loop",
          testBefore: true,
          loopMaximum: 1
        )

      {:ok, _} =
        Activity.add_loop_condition(
          loop,
          %{{@xsi, "type"} => "tFormalExpression"},
          "loopCounter < `4`"
        )

      {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
      {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

      {:ok, proc1} = Model.provision_process(pid, "proc1")
      :ok = Process.subscribe_log(proc1)

      initial_vars = Base.variables(proc1)

      assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
               Model.start(pid) |> List.keysort(0)

      assert_receive({Log, %Log.FlowNodeForward{id: "task"}})
      assert Base.variables(proc1) == Map.merge(initial_vars, %{"a" => 1})

      assert_receive(
        {Log, %Log.FlowNodeActivated{id: "end", token: %BPXE.Token{payload: %{"a" => var_a}}}}
      )

      assert var_a == 1
    end
  end
end
