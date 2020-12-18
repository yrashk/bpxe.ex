defmodule BPEXETest.Engine.PrecedenceGateway do
  use ExUnit.Case
  alias BPEXE.Engine.Instance
  alias BPEXE.Engine.Process
  alias BPEXE.Engine.Process.Log
  alias BPEXE.Engine.Event
  doctest BPEXE.Engine.PrecedenceGateway

  test "sends first message received (establishment of precedence)" do
    {:ok, pid} = Instance.start_link()
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

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

    {:ok, pg} = Process.add_precedence_gateway(proc1, "pg", %{"id" => "pg"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev1_pg", ev1, pg)

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev2_pg", ev2, pg)

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})

    {:ok, _} =
      Process.establish_sequence_flow(proc1, "ev1_t", pg, t1, %{
        {BPEXE.spec_schema(), "correspondsTo"} => "ev1_pg"
      })

    {:ok, _} =
      Process.establish_sequence_flow(proc1, "ev2_t", pg, t2, %{
        {BPEXE.spec_schema(), "correspondsTo"} => "ev2_pg"
      })

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventBasedGatewayActivated{id: "event_gate"}})
    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    assert_receive({Log, %Log.EventActivated{id: "ev2"}})

    signal(pid, "signal1")

    assert_receive({Log, %Log.PrecedenceGatewayPrecedenceEstablished{id: "pg"}})

    assert_receive({Log, %Log.TaskActivated{id: "t1"}})

    signal(pid, "signal2")
    refute_receive({Log, %Log.TaskActivated{id: "t2"}})
  end

  defp signal(instance, id) do
    :syn.publish({instance, :signal, id}, {BPEXE.Signal, id})
  end
end
