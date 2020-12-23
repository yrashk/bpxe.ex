defmodule BPXETest.Engine.Blueprint do
  use ExUnit.Case
  alias BPXE.Engine.Blueprint
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log
  alias BPXE.Engine.Event
  doctest Blueprint

  test "starting blueprint" do
    {:ok, _pid} = Blueprint.start_link()
  end

  test "blueprint's auto-generated ID should not be nil" do
    {:ok, pid} = Blueprint.start_link()
    assert Blueprint.config(pid).id != nil
  end

  test "adding processes and listing them" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, _} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})
    {:ok, _} = Blueprint.add_process(pid, "proc2", %{"id" => "proc2", "name" => "Proc 2"})

    assert Blueprint.processes(pid) |> Enum.sort() == ["proc1", "proc2"] |> Enum.sort()
  end

  test "starting an blueprint with no processes" do
    {:ok, pid} = Blueprint.start_link()
    assert {:error, :no_processes} == Blueprint.start(pid)
  end

  test "starting an blueprint with one process that has no start events" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, _} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, proc2} = Blueprint.add_process(pid, "proc2", %{"id" => "proc2", "name" => "Proc 2"})

    {:ok, _} = Process.add_event(proc2, "start", :startEvent, %{"id" => "start"})

    assert [{"proc1", {:error, :no_start_events}}, {"proc2", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)
  end

  test "should resume after a restart if we restore the state" do
    # Set up ETS flow handler
    {:ok, h} = BPXE.Engine.FlowHandler.ETS.new()

    me = self()
    id = make_ref()
    :syn.join({BPXE.Engine.Blueprint, id}, me)

    {:ok, pid} =
      BPXE.Engine.Blueprints.start_blueprint(
        flow_handler: h,
        id: id,
        init_fn: fn pid ->
          proc1 = restart_setup(pid)

          :ok = Process.subscribe_log(proc1, me)
          BPXE.Engine.Blueprint.restore_state(pid)
          send(me, {BPXE.Engine.Blueprint, :started, pid})
        end
      )

    receive do
      {BPXE.Engine.Blueprint, :started, _pid} -> :ok
    end

    BPXE.Engine.Blueprint.start(pid)

    assert_receive({Log, %Log.NewProcessActivation{activation: activation}})

    assert_receive({Log, %Log.FlowNodeActivated{id: "ev1", token: last_token}})
    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    # at this point, ev1 is ready to get a signal

    flush_messages()

    # but we crash the blueprint (and ensure activation is discarded to simulate the VM restart)
    BPXE.Engine.Process.Activation.discard(activation)
    :erlang.exit(pid, :kill)

    # wait until it restarts
    pid =
      receive do
        {BPXE.Engine.Blueprint, :started, pid} -> pid
      end

    # send it the signal
    # if it didn't recover the state, it won't actively listen for its signal
    signal(pid, "signal1")

    # and if it did listen, it should further activate t1
    assert_receive({Log, %Log.FlowNodeActivated{id: "t1", token: next_token}})
    # and the token is only one step away further
    assert BPXE.Token.distance(last_token, next_token) == 1
    assert_receive({Log, %Log.TaskActivated{id: "t1"}})

    # shutdown
    BPXE.Engine.Blueprints.stop_blueprint(pid)
  end

  test "should not resume after a restart if we don't restore the state" do
    # Set up ETS flow handler
    {:ok, h} = BPXE.Engine.FlowHandler.ETS.new()

    me = self()
    id = make_ref()
    :syn.join({BPXE.Engine.Blueprint, id}, me)

    {:ok, pid} =
      BPXE.Engine.Blueprints.start_blueprint(
        flow_handler: h,
        id: id,
        init_fn: fn pid ->
          proc1 = restart_setup(pid)

          :ok = Process.subscribe_log(proc1, me)
          send(me, {BPXE.Engine.Blueprint, :started, pid})
        end
      )

    receive do
      {BPXE.Engine.Blueprint, :started, _pid} -> :ok
    end

    BPXE.Engine.Blueprint.start(pid)

    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    # at this point, ev1 is ready to get a signal...

    flush_messages()

    # but we crash the blueprint (and ensure activation is discarded to simulate the VM restart)
    :erlang.exit(pid, :kill)

    # wait until it restarts
    pid =
      receive do
        {BPXE.Engine.Blueprint, :started, pid} -> pid
      end

    # send it the signal
    # if it didn't recover the state, it won't actively listen for its signal
    signal(pid, "signal1")

    # and if it did listen, it should further activate t1
    # (but in our case it didn't)
    refute_receive({Log, %Log.TaskActivated{id: "t1"}})

    # shutdown
    BPXE.Engine.Blueprints.stop_blueprint(pid)
  end

  defp signal(blueprint, id) do
    :syn.publish({blueprint, :signal, id}, {BPXE.Signal, id})
  end

  defp flush_messages() do
    receive do
      _m ->
        flush_messages()
    after
      1000 ->
        :ok
    end
  end

  def restart_setup(pid) do
    {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, the_end} = Process.add_event(proc1, "end", :endEvent, %{"id" => "end"})

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

    {:ok, _} = Process.establish_sequence_flow(proc1, "t1_", t1, the_end)
    {:ok, _} = Process.establish_sequence_flow(proc1, "t2_", t2, the_end)

    {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
    BPXE.Engine.Blueprint.synthesize(pid)
    proc1
  end
end
