defmodule BPEXETest.Proc.ParallelGateway do
  use ExUnit.Case
  alias BPEXE.Proc.Instance
  alias BPEXE.Proc.Process
  alias BPEXE.Proc.Process.Log
  alias BPEXE.Proc.FlowNode
  doctest Instance

  test "forking parallel gateway should send message to all forks" do
    {:ok, pid} = Instance.start_link(:ignored)
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", %{"id" => "start"}, :startEvent)
    {:ok, _} = FlowNode.add_outgoing(start, "s1")

    {:ok, _} =
      Process.add_sequence_flow(proc1, "s1", %{
        "id" => "s1",
        "sourceRef" => "start",
        "targetRef" => "fork"
      })

    {:ok, fork} = Process.add_parallel_gateway(proc1, "fork", %{"id" => "fork"})
    {:ok, _} = FlowNode.add_incoming(fork, "s1")
    {:ok, _} = FlowNode.add_outgoing(fork, "fork_1")
    {:ok, _} = FlowNode.add_outgoing(fork, "fork_2")

    {:ok, _} =
      Process.add_sequence_flow(proc1, "fork_1", %{
        "id" => "fork_1",
        "sourceRef" => "fork",
        "targetRef" => "t1"
      })

    {:ok, _} =
      Process.add_sequence_flow(proc1, "fork_2", %{
        "id" => "fork_2",
        "sourceRef" => "fork",
        "targetRef" => "t2"
      })

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})
    {:ok, _} = FlowNode.add_incoming(t1, "fork_1")
    {:ok, _} = FlowNode.add_incoming(t2, "fork_2")

    :ok = Process.listen_log(proc1)

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
    {:ok, _} = FlowNode.add_outgoing(start, "s1")

    {:ok, _} =
      Process.add_sequence_flow(proc1, "s1", %{
        "id" => "s1",
        "sourceRef" => "start",
        "targetRef" => "fork"
      })

    {:ok, fork} = Process.add_parallel_gateway(proc1, "fork", %{"id" => "fork"})
    {:ok, _} = FlowNode.add_incoming(fork, "s1")
    {:ok, _} = FlowNode.add_outgoing(fork, "fork_1")
    {:ok, _} = FlowNode.add_outgoing(fork, "fork_2")

    {:ok, _} =
      Process.add_sequence_flow(proc1, "fork_1", %{
        "id" => "fork_1",
        "sourceRef" => "fork",
        "targetRef" => "t1"
      })

    {:ok, _} =
      Process.add_sequence_flow(proc1, "fork_2", %{
        "id" => "fork_2",
        "sourceRef" => "fork",
        "targetRef" => "t2"
      })

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})
    {:ok, _} = FlowNode.add_incoming(t1, "fork_1")
    {:ok, _} = FlowNode.add_incoming(t2, "fork_2")

    {:ok, _} = FlowNode.add_outgoing(t1, "join_1")
    {:ok, _} = FlowNode.add_outgoing(t2, "join_2")

    {:ok, join} = Process.add_parallel_gateway(proc1, "join", %{"id" => "join"})
    {:ok, _} = FlowNode.add_incoming(join, "join_1")
    {:ok, _} = FlowNode.add_incoming(join, "join_2")

    {:ok, _} =
      Process.add_sequence_flow(proc1, "join_1", %{
        "id" => "join_1",
        "sourceRef" => "t1",
        "targetRef" => "join"
      })

    {:ok, _} =
      Process.add_sequence_flow(proc1, "join_2", %{
        "id" => "join_2",
        "sourceRef" => "t2",
        "targetRef" => "join"
      })

    {:ok, t3} = Process.add_task(proc1, "t3", :task, %{"id" => "t3"})
    {:ok, _} = FlowNode.add_incoming(t3, "t3s")
    {:ok, _} = FlowNode.add_outgoing(join, "t3s")

    {:ok, _} =
      Process.add_sequence_flow(proc1, "t3s", %{
        "id" => "t3s",
        "sourceRef" => "join",
        "targetRef" => "t3"
      })

    :ok = Process.listen_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive(
      {Log, %Log.FlowNodeActivated{id: "t3", message: %BPEXE.Message{content: [nil, nil]}}}
    )
  end
end
