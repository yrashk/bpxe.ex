defmodule BPXETest.Engine.EventBasedGateway do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Blueprint
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log
  alias BPXE.Engine.Event
  doctest BPXE.Engine.EventBasedGateway

  test "no event captured means no event-based branch will be chosen" do
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
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventBasedGatewayActivated{id: "event_gate"}})
    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    assert_receive({Log, %Log.EventActivated{id: "ev2"}})

    refute_receive({Log, %Log.TaskActivated{id: "t1"}})
    refute_receive({Log, %Log.TaskActivated{id: "t2"}})
  end

  test "one event captured should advance the flow and the other one will not be activated" do
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
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventBasedGatewayActivated{id: "event_gate"}})
    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    assert_receive({Log, %Log.EventActivated{id: "ev2"}})

    signal(pid, "signal1")

    assert_receive({Log, %Log.TaskActivated{id: "t1"}})

    signal(pid, "signal2")
    refute_receive({Log, %Log.TaskActivated{id: "t2"}})
  end

  test "one event captured should advance the flow and the other one will not be activated -- after re-synthesis" do
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

    Process.synthesize(proc1)
    Process.synthesize(proc1)

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventBasedGatewayActivated{id: "event_gate"}})
    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    assert_receive({Log, %Log.EventActivated{id: "ev2"}})

    signal(pid, "signal1")

    assert_receive({Log, %Log.TaskActivated{id: "t1"}})

    signal(pid, "signal2")
    refute_receive({Log, %Log.TaskActivated{id: "t2"}})
  end

  defp signal(blueprint, id) do
    :syn.publish({blueprint, :signal, id}, {BPXE.Signal, id})
  end
end
