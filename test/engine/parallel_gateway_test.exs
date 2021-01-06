defmodule BPXETest.Engine.ParallelGateway do
  use ExUnit.Case, async: true
  alias BPXE.Engine.{Model, Process, Task}
  alias BPXE.Engine.Process.Log
  doctest BPXE.Engine.ParallelGateway

  test "forking parallel gateway should send token to all forks" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, fork} = Process.add_parallel_gateway(proc1, id: "fork")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, t1} = Process.add_task(proc1, id: "t1")
    {:ok, t2} = Process.add_task(proc1, id: "t2")

    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_1", fork, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_2", fork, t2)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.ParallelGatewayReceived{id: "fork", from: "s1"}})
    assert_receive({Log, %Log.TaskActivated{id: "t1"}})
    assert_receive({Log, %Log.TaskActivated{id: "t2"}})
  end

  test "joining parallel gateway should send a combined tokend forward" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, fork} = Process.add_parallel_gateway(proc1, id: "fork")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, t1} = Process.add_script_task(proc1, id: "t1")
    {:ok, t2} = Process.add_script_task(proc1, id: "t2")

    {:ok, _} = Task.add_script(t1, ~s|
      flow.t1 = true
      |)

    {:ok, _} = Task.add_script(t2, ~s|
      flow.t2 = true
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_1", fork, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_2", fork, t2)

    {:ok, join} = Process.add_parallel_gateway(proc1, id: "join")

    {:ok, _} = Process.establish_sequence_flow(proc1, "join_1", t1, join)
    {:ok, _} = Process.establish_sequence_flow(proc1, "join_2", t2, join)

    {:ok, t3} = Process.add_task(proc1, id: "t3")
    {:ok, _} = Process.establish_sequence_flow(proc1, "s3", join, t3)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive(
      {Log,
       %Log.FlowNodeActivated{
         id: "t3",
         token: %BPXE.Token{payload: %{"t1" => true, "t2" => true}}
       }}
    )
  end

  test "joining parallel gateway with a threshold" do
    {:ok, pid} = Model.start_link()
    {:ok, proc1} = Model.add_process(pid, id: "proc1", name: "Proc 1")

    {:ok, start} = Process.add_start_event(proc1, id: "start")
    {:ok, fork} = Process.add_parallel_gateway(proc1, id: "fork")

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, t1} = Process.add_script_task(proc1, id: "t1")
    {:ok, t2} = Process.add_script_task(proc1, id: "t2")

    {:ok, _} = Task.add_script(t1, ~s|
      flow.t1 = true
      |)

    {:ok, _} = Task.add_script(t2, ~s|
      flow.t2 = true
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_1", fork, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_2", fork, t2)

    {:ok, join} =
      Process.add_parallel_gateway(proc1, %{
        "id" => "join",
        {BPXE.BPMN.ext_spec(), "joinThreshold"} => "1"
      })

    {:ok, _} = Process.establish_sequence_flow(proc1, "join_1", t1, join)
    {:ok, _} = Process.establish_sequence_flow(proc1, "join_2", t2, join)

    {:ok, t3} = Process.add_task(proc1, id: "t3")
    {:ok, _} = Process.establish_sequence_flow(proc1, "s3", join, t3)

    {:ok, proc1} = Model.provision_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Model.start(pid) |> List.keysort(0)

    assert_receive(
      {Log,
       %Log.FlowNodeActivated{
         id: "t3",
         token: %BPXE.Token{payload: payload}
       }}
    )

    # we should receive either t1's or t2's result
    assert payload["t1"] || payload["t2"]
  end
end
