defmodule BPEXETest.Proc.ParallelGateway do
  use ExUnit.Case
  alias BPEXE.Proc.Instance
  alias BPEXE.Proc.Process
  alias BPEXE.Proc.Process.Log
  doctest Instance

  test "forking parallel gateway should send message to all forks" do
    {:ok, pid} = Instance.start_link(:ignored)
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", %{"id" => "start"}, :startEvent)
    {:ok, fork} = Process.add_parallel_gateway(proc1, "fork", %{"id" => "fork"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_1", fork, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_2", fork, t2)

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.ParallelGatewayReceived{id: "fork", from: "s1"}})
    assert_receive({Log, %Log.TaskActivated{id: "t1"}})
    assert_receive({Log, %Log.TaskActivated{id: "t2"}})
  end

  test "joining parallel gateway should send a combined messaged forward" do
    {:ok, pid} = Instance.start_link(:ignored)
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", %{"id" => "start"}, :startEvent)
    {:ok, fork} = Process.add_parallel_gateway(proc1, "fork", %{"id" => "fork"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_1", fork, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_2", fork, t2)

    {:ok, join} = Process.add_parallel_gateway(proc1, "join", %{"id" => "join"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "join_1", t1, join)
    {:ok, _} = Process.establish_sequence_flow(proc1, "join_2", t2, join)

    {:ok, t3} = Process.add_task(proc1, "t3", :task, %{"id" => "t3"})
    {:ok, _} = Process.establish_sequence_flow(proc1, "s3", join, t3)

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive(
      {Log, %Log.FlowNodeActivated{id: "t3", message: %BPEXE.Message{content: [nil, nil]}}}
    )
  end

  test "joining parallel gateway with a threshold" do
    {:ok, pid} = Instance.start_link(:ignored)
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", %{"id" => "start"}, :startEvent)
    {:ok, fork} = Process.add_parallel_gateway(proc1, "fork", %{"id" => "fork"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_1", fork, t1)
    {:ok, _} = Process.establish_sequence_flow(proc1, "fork_2", fork, t2)

    {:ok, join} =
      Process.add_parallel_gateway(proc1, "join", %{
        "id" => "join",
        {BPEXE.spec_schema(), "joinThreshold"} => "1"
      })

    {:ok, _} = Process.establish_sequence_flow(proc1, "join_1", t1, join)
    {:ok, _} = Process.establish_sequence_flow(proc1, "join_2", t2, join)

    {:ok, t3} = Process.add_task(proc1, "t3", :task, %{"id" => "t3"})
    {:ok, _} = Process.establish_sequence_flow(proc1, "s3", join, t3)

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive(
      {Log, %Log.FlowNodeActivated{id: "t3", message: %BPEXE.Message{content: [nil]}}}
    )
  end
end
