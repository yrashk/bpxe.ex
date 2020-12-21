defmodule BPXETest.Engine.Task do
  use ExUnit.Case
  alias BPXE.Engine.Blueprint
  alias BPXE.Engine.{Process, Task, Base}
  alias BPXE.Engine.Process.Log
  doctest Task

  test "executes a script, captures state and retrieves it in other scripts" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, task} = Process.add_task(proc1, "task", :scriptTask, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, ~s|
      process.a = {}
      process.a.v = 1
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)

    {:ok, task2} = Process.add_task(proc1, "task2", :scriptTask, %{"id" => "task2"})
    {:ok, _} = Task.add_script(task2, ~s|
      process.a.v = process.a.v + 2
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, task2)

    {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.TaskCompleted{id: "task"}})
    assert_receive({Log, %Log.TaskCompleted{id: "task2"}})
    assert Base.variables(proc1) == %{"a" => %{"v" => 3}}
  end

  test "executes a script that modifies no state" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, task} = Process.add_task(proc1, "task", :scriptTask, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, ~s|
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)

    {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.TaskCompleted{id: "task"}})
    assert Base.variables(proc1) == %{}
  end

  test "executes a script that modifies token's payload" do
    {:ok, pid} = Blueprint.start_link()
    {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

    {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
    {:ok, the_end} = Process.add_event(proc1, "end", :endEvent, %{"id" => "end"})
    {:ok, task} = Process.add_task(proc1, "task", :scriptTask, %{"id" => "task"})
    {:ok, _} = Task.add_script(task, ~s|
      token.a = 1
      |)

    {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
    {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

    {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
    :ok = Process.subscribe_log(proc1)

    assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
             Blueprint.start(pid) |> List.keysort(0)

    assert_receive({Log, %Log.TaskCompleted{id: "task"}})

    assert_receive(
      {Log, %Log.FlowNodeActivated{id: "end", token: %BPXE.Token{payload: %{"a" => 1.0}}}}
    )
  end

  describe "serviceTask" do
    defmodule Service do
      use BPXE.Service, state: [called: false]

      def handle_request(%BPXE.Service.Request{payload: payload} = req, _blueprint, _from, state) do
        {:reply, %BPXE.Service.Response{payload: payload}, %{state | called: req}}
      end

      def handle_call(:state, _from, state) do
        {:reply, state, state}
      end
    end

    test "invokes registered services" do
      {:ok, pid} = Blueprint.start_link()
      {:ok, service} = BPXE.Service.start_link(Service)
      Blueprint.register_service(pid, "service", service)

      {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

      {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
      {:ok, the_end} = Process.add_event(proc1, "end", :endEvent, %{"id" => "end"})

      {:ok, task} =
        Process.add_task(proc1, "task", :serviceTask, %{
          "id" => "task",
          {BPXE.BPMN.ext_spec(), "name"} => "service",
          {BPXE.BPMN.ext_spec(), "resultVariable"} => "result"
        })

      {:ok, ext} = BPXE.Engine.FlowNode.add_extension_elements(task)
      BPXE.Engine.FlowNode.add_json(ext, %{"hello" => "world"})
      BPXE.Engine.FlowNode.add_json(ext, %{"world" => "goodbye"})

      {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
      {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

      {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
      :ok = Process.subscribe_log(proc1)

      assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
               Blueprint.start(pid) |> List.keysort(0)

      assert_receive({Log, %Log.TaskCompleted{id: "task"}})

      state = GenServer.call(service, :state)

      assert %BPXE.Service.Request{payload: [%{"hello" => "world"}, %{"world" => "goodbye"}]} =
               state.called

      assert_receive(
        {Log,
         %Log.FlowNodeActivated{
           id: "end",
           token: %BPXE.Token{
             payload: %{"result" => [%{"hello" => "world"}, %{"world" => "goodbye"}]}
           }
         }}
      )
    end

    test "should be able to use functionally derived payload (used in interpolation)" do
      {:ok, pid} = Blueprint.start_link()
      {:ok, service} = BPXE.Service.start_link(Service)
      Blueprint.register_service(pid, "service", service)

      {:ok, proc1} = Blueprint.add_process(pid, "proc1", %{"id" => "proc1", "name" => "Proc 1"})

      {:ok, start} = Process.add_event(proc1, "start", :startEvent, %{"id" => "start"})
      {:ok, the_end} = Process.add_event(proc1, "end", :endEvent, %{"id" => "end"})

      {:ok, task} =
        Process.add_task(proc1, "task", :serviceTask, %{
          "id" => "task",
          {BPXE.BPMN.ext_spec(), "name"} => "service",
          {BPXE.BPMN.ext_spec(), "resultVariable"} => "result"
        })

      {:ok, ext} = BPXE.Engine.FlowNode.add_extension_elements(task)

      # NB: we use elem(0) below to accommodate for the fact that `Task` DOES supply an encoder so that
      # BPMN interpolation can encode the value as needed if the input is not just one interpolated expression
      BPXE.Engine.FlowNode.add_json(ext, fn cb ->
        %{"hello" => cb.("return process.hello") |> elem(0)}
      end)

      BPXE.Engine.FlowNode.add_json(ext, fn cb ->
        %{"world" => cb.("return process.world") |> elem(0)}
      end)

      {:ok, _} = Process.establish_sequence_flow(proc1, "s1", start, task)
      {:ok, _} = Process.establish_sequence_flow(proc1, "s2", task, the_end)

      {:ok, proc1} = Blueprint.instantiate_process(pid, "proc1")
      Base.merge_variables(proc1, %{"hello" => "world", "world" => "goodbye"}, BPXE.Token.new())

      :ok = Process.subscribe_log(proc1)

      assert [{"proc1", [{"start", :ok}]}] |> List.keysort(0) ==
               Blueprint.start(pid) |> List.keysort(0)

      assert_receive({Log, %Log.TaskCompleted{id: "task"}})

      state = GenServer.call(service, :state)

      assert %BPXE.Service.Request{payload: [%{"hello" => "world"}, %{"world" => "goodbye"}]} =
               state.called

      assert_receive(
        {Log,
         %Log.FlowNodeActivated{
           id: "end",
           token: %BPXE.Token{
             payload: %{"result" => [%{"hello" => "world"}, %{"world" => "goodbye"}]}
           }
         }}
      )
    end
  end
end
