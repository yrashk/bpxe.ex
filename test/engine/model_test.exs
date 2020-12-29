defmodule BPXETest.Engine.Model do
  use ExUnit.Case, async: true
  alias BPXE.Engine.Model
  alias BPXE.Engine.Process
  alias BPXE.Engine.Process.Log
  alias BPXE.Engine.Event
  doctest Model

  test "starting model" do
    {:ok, _pid} = Model.start_link()
  end

  test "model's auto-generated ID should not be nil" do
    {:ok, pid} = Model.start_link()
    assert Model.config(pid).id != nil
  end

  test "adding processes and listing them" do
    {:ok, pid} = Model.start_link()
    {:ok, _} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})
    {:ok, _} = Model.add_process(pid, %{"id" => "proc2", "name" => "Proc 2"})

    assert Model.processes(pid) |> Enum.sort() == ["proc1", "proc2"] |> Enum.sort()
  end

  test "starting an model with no processes" do
    {:ok, pid} = Model.start_link()
    assert {:error, :no_processes} == Model.start(pid)
  end

  test "starting an model with one process that has no start events" do
    {:ok, pid} = Model.start_link()
    {:ok, _} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, proc2} = Model.add_process(pid, %{"id" => "proc2", "name" => "Proc 2"})

    {:ok, _} = Process.add_start_event(proc2, %{"id" => "start"})

    assert [{"proc1", {:error, :no_start_events}}, {"proc2", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)
  end

  test "should resume after a restart if we restore the state" do
    # Set up ETS flow handler
    {:ok, h} = BPXE.Engine.FlowHandler.ETS.new()

    me = self()
    id = make_ref()
    :syn.join({BPXE.Engine.Model, id}, me)

    {:ok, pid} =
      BPXE.Engine.Models.start_model(
        flow_handler: h,
        id: id,
        init_fn: fn pid ->
          proc1 = restart_setup(pid)

          :ok = Process.subscribe_log(proc1, me)
          BPXE.Engine.Model.restore_state(pid)
          send(me, {BPXE.Engine.Model, :started, pid})
        end
      )

    receive do
      {BPXE.Engine.Model, :started, _pid} -> :ok
    end

    BPXE.Engine.Model.start(pid)

    assert_receive({Log, %Log.NewProcessActivation{activation: activation}})

    assert_receive({Log, %Log.FlowNodeActivated{id: "ev1", token: last_token}})
    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    # at this point, ev1 is ready to get a signal

    flush_messages()

    # but we crash the model (and ensure activation is discarded to simulate the VM restart)
    BPXE.Engine.Process.Activation.discard(activation)
    :erlang.exit(pid, :kill)

    # wait until it restarts
    pid =
      receive do
        {BPXE.Engine.Model, :started, pid} -> pid
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
    BPXE.Engine.Models.stop_model(pid)
  end

  test "should not resume after a restart if we don't restore the state" do
    # Set up ETS flow handler
    {:ok, h} = BPXE.Engine.FlowHandler.ETS.new()

    me = self()
    id = make_ref()
    :syn.join({BPXE.Engine.Model, id}, me)

    {:ok, pid} =
      BPXE.Engine.Models.start_model(
        flow_handler: h,
        id: id,
        init_fn: fn pid ->
          proc1 = restart_setup(pid)

          :ok = Process.subscribe_log(proc1, me)
          send(me, {BPXE.Engine.Model, :started, pid})
        end
      )

    receive do
      {BPXE.Engine.Model, :started, _pid} -> :ok
    end

    BPXE.Engine.Model.start(pid)

    assert_receive({Log, %Log.EventActivated{id: "ev1"}})
    # at this point, ev1 is ready to get a signal...

    flush_messages()

    # but we crash the model (and ensure activation is discarded to simulate the VM restart)
    :erlang.exit(pid, :kill)

    # wait until it restarts
    pid =
      receive do
        {BPXE.Engine.Model, :started, pid} -> pid
      end

    # send it the signal
    # if it didn't recover the state, it won't actively listen for its signal
    signal(pid, "signal1")

    # and if it did listen, it should further activate t1
    # (but in our case it didn't)
    refute_receive({Log, %Log.TaskActivated{id: "t1"}})

    # shutdown
    BPXE.Engine.Models.stop_model(pid)
  end

  defp signal(model, id) do
    :syn.publish({model, :signal, id}, {BPXE.Signal, id})
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
    {:ok, proc1} = Model.add_process(pid, %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_start_event(proc1, %{"id" => "start"})
    {:ok, the_end} = Process.add_end_event(proc1, %{"id" => "end"})

    {:ok, event_gate} = Process.add_event_based_gateway(proc1, %{"id" => "event_gate"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, event_gate)

    {:ok, ev1} = Process.add_intermediate_catch_event(proc1, %{"id" => "ev1"})
    {:ok, _} = Event.add_signal_event_definition(ev1, %{"signalRef" => "signal1"})

    {:ok, ev2} = Process.add_intermediate_catch_event(proc1, %{"id" => "ev2"})
    {:ok, _} = Event.add_signal_event_definition(ev2, %{"signalRef" => "signal2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "event_gate_1", event_gate, ev1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "event_gate_2", event_gate, ev2)

    {:ok, t1} = Process.add_task(proc1, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, %{"id" => "t2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "ev1_t", ev1, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "ev2_t", ev2, t2)

    {:ok, _} = Process.establish_sequence_flow(proc1, "t1_", t1, the_end)
    {:ok, _} = Process.establish_sequence_flow(proc1, "t2_", t2, the_end)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    BPXE.Engine.Model.synthesize(pid)
    proc1
  end
end
