defmodule BPXETest.Engine.PropertyContainer do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Model
  alias BPXE.Engine.{PropertyContainer, Process, Task}
  alias BPXE.Engine.Process.Log
  doctest BPXE.Engine.PropertyContainer

  test "declared property enters the token payload but doesn't override it" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_script_task(proc1, id: "task")
    {:ok, _} = Task.add_script(task, ~s|
      flow.a = true
      |)

    PropertyContainer.add_property(task, %{
      "id" => "prop1",
      "name" => "a",
      {BPXE.BPMN.ext_spec(), "flow"} => "true"
    })

    PropertyContainer.add_property(task, %{
      "id" => "prop2",
      "name" => "b",
      {BPXE.BPMN.ext_spec(), "flow"} => "true"
    })

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
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_script_task(proc1, id: "task")
    {:ok, _} = Task.add_script(task, ~s|
      flow.a = true
      flow_node.b = "hello"
      |)

    PropertyContainer.add_property(task, %{
      "id" => "prop1",
      "name" => "a",
      {BPXE.BPMN.ext_spec(), "flow"} => "true"
    })

    PropertyContainer.add_property(task, id: "prop2", name: "b")

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
