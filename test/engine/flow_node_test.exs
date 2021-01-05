defmodule BPXETest.Engine.FlowNode do
  use ExUnit.Case, async: true
  alias BPXE.Engine.{Model, Process, Task, SequenceFlow, FlowNode}
  alias Process.Log
  doctest BPXE.Engine.FlowNode

  @xsi "http://www.w3.org/2001/XMLSchema-instance"

  test "sequence flow with no condition proceeds" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})
    {:ok, the_end} = Process.add_end_event(proc1, %{"id" => "end"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventActivated{id: "start"}})
    assert_receive({Log, %Log.EventActivated{id: "end"}})
  end

  test "sequence flow with a truthful condition proceeds" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})
    {:ok, the_end} = Process.add_end_event(proc1, %{"id" => "end"})

    {:ok, sf} = Process.establish_sequence_flow(proc1, "s1", start, the_end)

    SequenceFlow.add_condition_expression(sf, %{{@xsi, "type"} => "tFormalExpression"}, "`true`")

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventActivated{id: "start"}})
    assert_receive({Log, %Log.EventActivated{id: "end"}})
  end

  test "sequence flow with a falsy condition does not proceed" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})
    {:ok, the_end} = Process.add_end_event(proc1, %{"id" => "end"})

    {:ok, sf} = Process.establish_sequence_flow(proc1, "s1", start, the_end)

    SequenceFlow.add_condition_expression(
      sf,
      %{{@xsi, "type"} => "tFormalExpression"},
      "`false`"
    )

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventActivated{id: "start"}})
    refute_receive({Log, %Log.EventActivated{id: "end"}})
  end

  test "sequence flow conditions have access to all necessary variables" do
    # Current list:
    # `process` -- unbounded dictionary for process state
    # `flow_node` -- current flow_node
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})
    {:ok, task} = Process.add_script_task(proc1, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, %{}, ~s|
      process.proceed = true 
      flow_node.test = flow_node.id
      |)
    {:ok, the_end} = Process.add_end_event(proc1, %{"id" => "end"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, sf} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    # Ensure we have access to `process`
    SequenceFlow.add_condition_expression(
      sf,
      %{{@xsi, "type"} => "tFormalExpression"},
      ~s|process.proceed && flow_node.test == `"task"`|
    )

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventActivated{id: "start"}})
    assert_receive({Log, %Log.TaskActivated{id: "task"}})
    assert_receive({Log, %Log.EventActivated{id: "end"}})
  end

  test "sequence flow conditions error will result in a log entry" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})
    {:ok, the_end} = Process.add_end_event(proc1, %{"id" => "end"})

    {:ok, sf} = Process.establish_sequence_flow(proc1, "s1", start, the_end)

    SequenceFlow.add_condition_expression(
      sf,
      %{{@xsi, "type"} => "tFormalExpression"},
      ~s|this is an invalid expression|
    )

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive {Log,
                    %Log.ExpressionErrorOccurred{
                      id: "s1",
                      expression: "this is an invalid expression"
                    }}

    refute_receive({Log, %Log.FlowNodeActivated{id: "end"}})
  end

  test "declared flow property enters the token payload but doesn't override it" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})
    {:ok, the_end} = Process.add_end_event(proc1, %{"id" => "end"})

    {:ok, task} = Process.add_script_task(proc1, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, %{}, ~s|
      flow.a = true
      |)

    FlowNode.add_property(task, %{"id" => "prop1", "name" => "a", "flow" => "true"})
    FlowNode.add_property(task, %{"id" => "prop2", "name" => "b", "flow" => "true"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive(
      {Log,
       %Log.FlowNodeActivated{id: "end", token: %BPXE.Token{payload: %{"a" => true, "b" => nil}}}}
    )
  end

  test "finding flow and non-flow properties" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})
    {:ok, the_end} = Process.add_end_event(proc1, %{"id" => "end"})

    {:ok, task} = Process.add_script_task(proc1, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, %{}, ~s|
      flow.a = true
      flow_node.b = "hello"
      |)

    FlowNode.add_property(task, %{"id" => "prop1", "name" => "a", "flow" => "true"})
    FlowNode.add_property(task, %{"id" => "prop2", "name" => "b"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.FlowNodeActivated{id: "end", token: token}})

    assert Process.get_property(proc1, "prop1", token) == true
    assert Process.get_property(proc1, "prop2") == "hello"
  end
end
