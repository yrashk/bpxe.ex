defmodule BPXETest.Engine.SensorGateway do
  use ExUnit.Case
  alias BPXE.Engine.{Blueprint, Process, FlowNode}
  alias BPXE.Engine.Process.Log
  doctest BPXE.Engine.SensorGateway

  @xsi "http://www.w3.org/2001/XMLSchema-blueprint"
  test "sends completion notification with fired sequence flows" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})

    {:ok, fork} = Process.add_parallel_gateway(proc1, "fork", %{"id" => "fork"})
    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, fork)

    {:ok, sensor} = Process.add_sensor_gateway(proc1, "sensor", %{"id" => "sensor"})

    {:ok, t1sf} = Process.establish_sequence_flow(proc1, "fork_1", fork, sensor)
    {:ok, t2sf} = Process.establish_sequence_flow(proc1, "fork_2", fork, sensor)
    {:ok, t3sf} = Process.establish_sequence_flow(proc1, "fork_3", fork, sensor)
    {:ok, _} = Process.establish_sequence_flow(proc1, "completion", fork, sensor)

    FlowNode.add_condition_expression(
      t1sf,
      %{{@xsi, "type"} => "tFormalExpression"},
      "return true"
    )

    FlowNode.add_condition_expression(
      t2sf,
      %{{@xsi, "type"} => "tFormalExpression"},
      "return true"
    )

    FlowNode.add_condition_expression(
      t3sf,
      %{{@xsi, "type"} => "tFormalExpression"},
      "return false"
    )

    {:ok, join} = Process.add_parallel_gateway(proc1, "join", %{"id" => "join"})

    {:ok, sensor_reader} =
      Process.add_task(proc1, "sensorReader", :task, %{"id" => "sensorReader"})

    {:ok, _} = Process.establish_sequence_flow(proc1, "join_1", sensor, join)
    {:ok, _} = Process.establish_sequence_flow(proc1, "join_2", sensor, join)
    {:ok, _} = Process.establish_sequence_flow(proc1, "join_3", sensor, join)

    {:ok, _} = Process.establish_sequence_flow(proc1, "sensorReading", sensor, sensor_reader)

    {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive(
      {Log,
       %Log.FlowNodeActivated{
         id: "sensorReader",
         token: %BPXE.Token{payload: %BPXE.Engine.SensorGateway.Token{fired: fired}}
       }}
    )

    # Join should activate
    assert_receive({Log, %Log.FlowNodeActivated{id: "join"}})
    # But not complete (not enough firings)
    assert_receive({Log, %Log.ParallelGatewayReceived{id: "join", from: "join_1"}})
    assert_receive({Log, %Log.ParallelGatewayReceived{id: "join", from: "join_2"}})
    refute_receive({Log, %Log.ParallelGatewayReceived{id: "join", from: "join_3"}})
    # refute_receive({Log, %Log.ParallelGatewayCompleted{id: "join"}})

    assert fired |> Enum.sort() == [0, 1]
  end
end