defmodule BPXETest.Engine.DataOutputAssociation do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Model
  alias BPXE.Engine.{PropertyContainer, Process, DataOutputAssociation, FlowNode}
  alias BPXE.Engine.Process.Log
  doctest BPXE.Engine.DataOutputAssociation

  test "copies property into a data object after flow node activation" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_task(proc1, id: "task")

    PropertyContainer.add_property(task,
      id: "prop1",
      name: "a"
    )

    {:ok, _} = Process.add_data_object(proc1, id: "do1")

    {:ok, _} = DataOutputAssociation.add(task, source: "prop1", target: "do1")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    task = FlowNode.whereis(pid, "task")
    PropertyContainer.set_property(task, "prop1", 1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.FlowNodeForward{id: "task"}})

    {:ok, data_object} = Process.data_object(proc1, "do1")
    assert data_object.value == 1
  end

  test "will copy back into the same node" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_task(proc1, id: "task")

    PropertyContainer.add_property(task,
      id: "prop1",
      name: "a"
    )

    PropertyContainer.add_property(task,
      id: "prop2",
      name: "b"
    )

    {:ok, _} = DataOutputAssociation.add(task, source: "prop1", target: "prop2")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    task = FlowNode.whereis(pid, "task")
    PropertyContainer.set_property(task, "prop1", 1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.FlowNodeForward{id: "task"}})

    assert PropertyContainer.get_property(task, "prop2") == {:ok, 1}
  end

  test "copies into process property after flow node activation" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_task(proc1, id: "task")

    PropertyContainer.add_property(task,
      id: "prop1",
      name: "a"
    )

    PropertyContainer.add_property(proc1, id: "propP", name: "propP")

    {:ok, _} = DataOutputAssociation.add(task, source: "prop1", target: "propP")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    task = FlowNode.whereis(pid, "task")
    PropertyContainer.set_property(task, "prop1", 1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.FlowNodeForward{id: "task"}})

    assert PropertyContainer.get_property(proc1, "propP") == {:ok, 1}
  end

  test "copies multiple associations" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_task(proc1, id: "task")

    PropertyContainer.add_property(task,
      id: "prop1",
      name: "a"
    )

    {:ok, _} = Process.add_data_object(proc1, id: "do1")
    {:ok, _} = Process.add_data_object(proc1, id: "do2")

    {:ok, _} = DataOutputAssociation.add(task, source: "prop1", target: "do1")
    {:ok, _} = DataOutputAssociation.add(task, source: "prop1", target: "do2")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    task = FlowNode.whereis(pid, "task")
    PropertyContainer.set_property(task, "prop1", 1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.FlowNodeForward{id: "task"}})

    {:ok, data_object} = Process.data_object(proc1, "do1")
    assert data_object.value == 1

    {:ok, data_object} = Process.data_object(proc1, "do2")
    assert data_object.value == 1
  end
end
