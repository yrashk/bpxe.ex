defmodule BPXETest.Engine.Process do
  use ExUnit.Case
  alias BPXE.Engine.Blueprint
  alias BPXE.Engine.Process
  alias BPXE.Engine.Event
  doctest Process

  test "re-synthesizing flow nodes doesn't do anything" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})

    {:ok, event_gate} =
      Process.add_event_based_gateway(proc1, "event_gate", %{"id" => "event_gate"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, event_gate)

    {:ok, ev1} = Process.add_event(proc1, "ev1", :intermediateCatchEvent, %{"id" => "ev1"})
    {:ok, _} = Event.add_signal_event_definition(ev1, %{"signalRef" => "signal1"})

    {:ok, ev2} = Process.add_event(proc1, "ev2", :intermediateCatchEvent, %{"id" => "ev1"})
    {:ok, _} = Event.add_signal_event_definition(ev2, %{"signalRef" => "signal2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "event_gate_1", event_gate, ev1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "event_gate_2", event_gate, ev2)

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev1_t", ev1, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "ev2_t", ev2, t2)

    {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")

    flow_nodes_count = Process.flow_nodes(proc1) |> length()

    Process.synthesize(proc1)
    flow_nodes_count_1 = Process.flow_nodes(proc1) |> length()
    assert flow_nodes_count_1 > flow_nodes_count

    Process.synthesize(proc1)
    flow_nodes_count_2 = Process.flow_nodes(proc1) |> length()
    assert flow_nodes_count_2 == flow_nodes_count_1
  end
end
