defmodule BPXETest.Engine.DataInputAssociation do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Model
  alias BPXE.Engine.{PropertyContainer, Process, DataInputAssociation, FlowNode}
  alias BPXE.Engine.Process.Log
  doctest BPXE.Engine.DataInputAssociation

  test "copies data object into a property after flow node activation" do
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

    {:ok, _} = DataInputAssociation.add(task, source: "do1", target: "prop1")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    {:ok, data_object} = Process.data_object(proc1, "do1")
    Process.update_data_object(proc1, %{data_object | value: 1})

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.FlowNodeForward{id: "task"}})

    task = FlowNode.whereis(pid, "task")
    assert PropertyContainer.get_property(task, "prop1") == {:ok, 1}
  end

  test "does not copy to a data object (outside of flow node)" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_task(proc1, id: "task")

    {:ok, _} = Process.add_data_object(proc1, id: "do1")
    {:ok, _} = Process.add_data_object(proc1, id: "do2")

    {:ok, _} = DataInputAssociation.add(task, source: "do1", target: "do2")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    {:ok, data_object} = Process.data_object(proc1, "do1")
    Process.update_data_object(proc1, %{data_object | value: 1})

    {:ok, data_object} = Process.data_object(proc1, "do2")
    Process.update_data_object(proc1, %{data_object | value: 2})

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive(
      {Log, %Log.FlowNodeErrorOccurred{id: "task", error: {:target_ref_not_found, "do2"}}}
    )

    {:ok, data_object} = Process.data_object(proc1, "do2")
    assert data_object.value == 2
  end

  test "copies process property into a flow node property after flow node activation" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_task(proc1, id: "task")

    PropertyContainer.add_property(task,
      id: "prop1",
      name: "a"
    )

    {:ok, _} = PropertyContainer.add_property(proc1, id: "propP", name: "propP")

    {:ok, _} = DataInputAssociation.add(task, source: "propP", target: "prop1")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    PropertyContainer.set_property(proc1, "propP", 1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.FlowNodeForward{id: "task"}})

    task = FlowNode.whereis(pid, "task")
    assert PropertyContainer.get_property(task, "prop1") == {:ok, 1}
  end

  test "does not copy to a process property (outside of flow node)" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, the_end} = Process.add_end_event(proc1, id: "end")

    {:ok, task} = Process.add_task(proc1, id: "task")

    PropertyContainer.add_property(task,
      id: "prop1",
      name: "a"
    )

    {:ok, _} = PropertyContainer.add_property(proc1, id: "propP", name: "propP")
    {:ok, _} = PropertyContainer.add_property(proc1, id: "propD", name: "propD")

    {:ok, _} = DataInputAssociation.add(task, source: "propP", target: "propD")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    PropertyContainer.set_property(proc1, "propP", 1)
    PropertyContainer.set_property(proc1, "propD", 2)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive(
      {Log, %Log.FlowNodeErrorOccurred{id: "task", error: {:target_ref_not_found, "propD"}}}
    )

    assert PropertyContainer.get_property(proc1, "propD") == {:ok, 2}
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

    PropertyContainer.add_property(task,
      id: "prop2",
      name: "b"
    )

    {:ok, _} = Process.add_data_object(proc1, id: "do1")

    {:ok, _} = DataInputAssociation.add(task, source: "do1", target: "prop1")
    {:ok, _} = DataInputAssociation.add(task, source: "do1", target: "prop2")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    {:ok, data_object} = Process.data_object(proc1, "do1")
    Process.update_data_object(proc1, %{data_object | value: 1})

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.FlowNodeForward{id: "task"}})

    task = FlowNode.whereis(pid, "task")
    assert PropertyContainer.get_property(task, "prop1") == {:ok, 1}
    assert PropertyContainer.get_property(task, "prop2") == {:ok, 1}
  end
end
