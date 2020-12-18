defmodule BPEXETest.Engine.FlowNode do
  use ExUnit.Case
  alias BPEXE.Engine.{Instance, Process, FlowNode}
  alias Process.Log
  doctest BPEXE.Engine.FlowNode

  @xsi "http://www.w3.org/2001/XMLSchema-instance"

  test "sequence flow with no condition proceeds" do
    {:ok, pid} = Instance.start_link()
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, the_end} = Process.add_event(proc1, "end", :endEvent, %{"id" => "end"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, the_end)

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventActivated{id: "start"}})
    assert_receive({Log, %Log.EventActivated{id: "end"}})
  end

  test "sequence flow with a truthful condition proceeds" do
    {:ok, pid} = Instance.start_link()
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, the_end} = Process.add_event(proc1, "end", :endEvent, %{"id" => "end"})

    {:ok, sf} = Process.establish_sequence_flow(proc1, "s1", start, the_end)

    FlowNode.add_condition_expression(sf, %{{@xsi, "type"} => "tFormalExpression"}, "return true")

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventActivated{id: "start"}})
    assert_receive({Log, %Log.EventActivated{id: "end"}})
  end

  test "sequence flow with a falsy condition does not proceed" do
    {:ok, pid} = Instance.start_link()
    {:ok, proc1} = Instance.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, the_end} = Process.add_event(proc1, "end", :endEvent, %{"id" => "end"})

    {:ok, sf} = Process.establish_sequence_flow(proc1, "s1", start, the_end)

    FlowNode.add_condition_expression(
      sf,
      %{{@xsi, "type"} => "tFormalExpression"},
      "return false"
    )

    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Instance.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.EventActivated{id: "start"}})
    refute_receive({Log, %Log.EventActivated{id: "end"}})
  end
end
