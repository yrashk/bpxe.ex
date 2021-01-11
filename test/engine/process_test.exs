defmodule BPXETest.Engine.Process do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Model
  alias BPXE.Engine.Process
  alias BPXE.Engine.Event
  doctest Process

  test "re-synthesizing flow nodes doesn't do anything" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")

    {:ok, event_gate} = Process.add_event_based_gateway(proc1, id: "event_gate")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, event_gate)

    {:ok, ev1} = Process.add_intermediate_catch_event(proc1, id: "ev2")
    {:ok, _} = Event.add_signal_event_definition(ev1, signalRef: "signal1")

    {:ok, ev2} = Process.add_intermediate_catch_event(proc1, id: "ev2")
    {:ok, _} = Event.add_signal_event_definition(ev2, signalRef: "signal2")

    {:ok, _} = Process.establish_sequence_flow(proc1, "event_gate_1", event_gate, ev1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "event_gate_2", event_gate, ev2)

    {:ok, t1} = Process.add_task(proc1, id: "t1")
    {:ok, t2} = Process.add_task(proc1, id: "t2")

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev1_t", ev1, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "ev2_t", ev2, t2)

    {:ok, proc1} = Model.provision_process(pid, "proc1")

    flow_nodes_count = Process.flow_nodes(proc1) |> length()

    Process.synthesize(proc1)
    flow_nodes_count_1 = Process.flow_nodes(proc1) |> length()
    assert flow_nodes_count_1 > flow_nodes_count

    Process.synthesize(proc1)
    flow_nodes_count_2 = Process.flow_nodes(proc1) |> length()
    assert flow_nodes_count_2 == flow_nodes_count_1
  end

  test "process activations in different processes should differ" do
    # ...otherwise they will collide in flow handlers
    {:ok, pid} = Model.start_link()
    {:ok, _} = Model.add_process(pid, id: "proc1", name: "Proc 1")
    {:ok, _} = Model.add_process(pid, id: "proc2", name: "Proc 2")

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    {:ok, proc2} = Model.provision_process(pid, "proc2")

    assert Process.new_activation(proc1) != Process.new_activation(proc2)
  end

  test "registering a data object" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, _} = Process.add_data_object(proc1, id: "do1")

    {:ok, proc1} = Model.provision_process(pid, "proc1")

    {:ok, data_object} = Process.data_object(proc1, "do1")

    assert data_object.attrs["id"] == "do1"
  end

  test "registering a data object with a state" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, do1} = Process.add_data_object(proc1, id: "do1")
    BPXE.Engine.DataObject.add_data_state(do1, name: "init")

    {:ok, proc1} = Model.provision_process(pid, "proc1")

    {:ok, data_object} = Process.data_object(proc1, "do1")

    assert data_object.state == "init"
  end

  test "updating a data object" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, _} = Process.add_data_object(proc1, id: "do1")

    {:ok, proc1} = Model.provision_process(pid, "proc1")

    {:ok, data_object} = Process.data_object(proc1, "do1")
    Process.update_data_object(proc1, %{data_object | value: 1})

    {:ok, data_object} = Process.data_object(proc1, "do1")
    assert data_object.value == 1
  end

  test "registering a data object reference" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, _} = Process.add_data_object(proc1, id: "do1")
    {:ok, _} = Process.add_data_object_reference(proc1, id: "do1ref", dataObjectRef: "do1")

    {:ok, proc1} = Model.provision_process(pid, "proc1")

    {:ok, %BPXE.Engine.DataObject{attrs: %{"id" => "do1"}}} = Process.data_object(proc1, "do1ref")
  end

  test "registering a data object reference with a state" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, _} = Process.add_data_object(proc1, id: "do1")
    {:ok, do1ref} = Process.add_data_object_reference(proc1, id: "do1ref", dataObjectRef: "do1")
    BPXE.Engine.DataObject.add_data_state(do1ref, name: "init")

    {:ok, proc1} = Model.provision_process(pid, "proc1")

    {:ok, data_object} = Process.data_object(proc1, "do1")
    assert data_object.state == nil

    {:ok, data_object_reference} = Process.data_object_reference(proc1, "do1ref")
    assert data_object_reference.state == "init"
  end
end
