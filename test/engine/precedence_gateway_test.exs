defmodule BPXETest.Engine.PrecedenceGateway do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Model
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log
  alias BPXE.Engine.Event
  doctest BPXE.Engine.PrecedenceGateway

  test "sends first token received (establishment of precedence)" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})

    {:ok, event_gate} = Process.add_event_based_gateway(proc1, %{"id" => "event_gate"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, event_gate)

    {:ok, ev1} = Process.add_intermediate_catch_event(proc1, %{"id" => "ev1"})
    {:ok, _} = Event.add_signal_event_definition(ev1, %{"signalRef" => "signal1"})

    {:ok, ev2} = Process.add_intermediate_catch_event(proc1, %{"id" => "ev2"})
    {:ok, _} = Event.add_signal_event_definition(ev2, %{"signalRef" => "signal2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "event_gate_1", event_gate, ev1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "event_gate_2", event_gate, ev2)

    {:ok, pg} = Process.add_precedence_gateway(proc1, %{"id" => "pg"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev1_pg", ev1, pg)

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev2_pg", ev2, pg)

    {:ok, t1} = Process.add_task(proc1, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, %{"id" => "t2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev1_t", pg, t1, %{})

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev2_t", pg, t2, %{})

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventBasedGatewayActivated{id: "event_gate"}})
    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    assert_receive({Log, %Log.EventActivated{id: "ev2"}})

    signal(pid, "signal1")

    assert_receive({Log, %Log.PrecedenceGatewayPrecedenceEstablished{id: "pg"}})

    assert_receive({Log, %Log.TaskActivated{id: "t1"}})

    signal(pid, "signal2")
    refute_receive({Log, %Log.TaskActivated{id: "t2"}})
  end

  defp signal(model, id) do
    :syn.publish({model, :signal, id}, {BPXE.Signal, id})
  end
end
