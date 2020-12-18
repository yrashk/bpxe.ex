defmodule BPXETest.Engine.InclusiveGateway do
  use ExUnit.Case
  alias BPXE.Engine.Instance
  alias BPXE.Engine.{Process, FlowNode}
  alias BPXE.Engine.Process.Log
  doctest BPXE.Engine.InclusiveGateway

  @xsi "http://www.w3.org/2001/XMLSchema-instance"

  test "forking inclusive gateway should send message to all forks that have truthful conditions" do
    {:ok, pid} = Instance.start_link()
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, fork} = Process.add_inclusive_gateway(proc1, "fork", %{"id" => "fork"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})

    {:ok, f1} = Process.establish_sequence_flow(proc1, "fork_1", fork, t1)
    {:ok, f2} = Process.establish_sequence_flow(proc1, "fork_2", fork, t2)

    FlowNode.add_condition_expression(
      f1,
      %{{@xsi, "type"} => "tFormalExpression"},
      "return true"
    )

    FlowNode.add_condition_expression(
      f2,
      %{{@xsi, "type"} => "tFormalExpression"},
      "return false"
    )

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.InclusiveGatewayReceived{id: "fork", from: "s1"}})
    assert_receive({Log, %Log.TaskActivated{id: "t1"}})
    refute_receive({Log, %Log.TaskActivated{id: "t2"}})
  end

  test "joining inclusive gateway should send a combined messaged forward, only from forks that had truthful conditions" do
    {:ok, pid} = Instance.start_link()
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, fork} = Process.add_inclusive_gateway(proc1, "fork", %{"id" => "fork"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, t1} = Process.add_task(proc1, "t1", :task, %{"id" => "t1"})
    {:ok, t2} = Process.add_task(proc1, "t2", :task, %{"id" => "t2"})
    {:ok, t3} = Process.add_task(proc1, "t3", :task, %{"id" => "t3"})

    {:ok, f1} = Process.establish_sequence_flow(proc1, "fork_1", fork, t1)
    {:ok, f2} = Process.establish_sequence_flow(proc1, "fork_2", fork, t2)
    {:ok, f3} = Process.establish_sequence_flow(proc1, "fork_3", fork, t3)

    FlowNode.add_condition_expression(
      f3,
      %{{@xsi, "type"} => "tFormalExpression"},
      "return false"
    )

    {:ok, join} = Process.add_inclusive_gateway(proc1, "join", %{"id" => "join"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "join_1", t1, join)
    {:ok, _} = Process.establish_sequence_flow(proc1, "join_2", t2, join)
    {:ok, _} = Process.establish_sequence_flow(proc1, "join_3", t3, join)

    {:ok, t4} = Process.add_task(proc1, "t4", :task, %{"id" => "t4"})
    {:ok, _} = Process.establish_sequence_flow(proc1, "s4", join, t4)

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    # We should receive a collection of two messages (third condition was falsy)
    assert_receive(
      {Log, %Log.FlowNodeActivated{id: "t4", message: %BPXE.Message{content: [nil, nil]}}}
    )
  end
end
