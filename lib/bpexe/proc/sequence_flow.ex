defmodule BPEXE.Proc.SequenceFlow do
  use GenServer
  use BPEXE.Proc.Base
  alias BPEXE.Proc.Process
  alias BPEXE.Proc.Process.Log

  defstruct id: nil, options: %{}, instance: nil, process: nil, buffer: %{}, process_id: nil

  def start_link(id, options, instance, process) do
    # This way we can wait until it is initialized
    :proc_lib.start_link(__MODULE__, :init, [{id, options, instance, process}])
  end

  def init({id, options, instance, process}) do
    :syn.join({instance.pid, :flow_in, id}, self())

    # Done initializing
    :proc_lib.init_ack({:ok, self()})

    state = %__MODULE__{
      id: id,
      options: options,
      instance: instance,
      process: process,
      process_id: Process.id(process)
    }

    init_recoverable(state)

    :gen_server.enter_loop(__MODULE__, [], state)
  end

  def handle_info({BPEXE.Message.Ack, token, _id}, state) do
    state = %{state | buffer: Map.delete(state.buffer, token)}
    save_state(state, [state.options["targetRef"]])
    {:noreply, state}
  end

  def handle_info({%BPEXE.Message{token: token, __invisible__: true} = msg, id}, state) do
    :syn.publish({state.instance.pid, :flow_out, id}, {msg, id})
    save_state(state, [state.options["sourceRef"], state.options["targetRef"]]) # FIXME
    {:noreply, state}
  end

  def handle_info({%BPEXE.Message{token: token, __invisible__: false} = msg, id}, state) do
    Process.log(state.process, %Log.SequenceFlowStarted{
      pid: self(),
      id: state.id,
      token: token
    })

    :syn.publish({state.instance.pid, :flow_out, id}, {msg, id})

    Process.log(state.process, %Log.SequenceFlowCompleted{
      pid: self(),
      id: state.id,
      token: token
    })

    state = %{state | buffer: Map.put(state.buffer, token, msg)}
    save_state(state, [state.options["sourceRef"]])
    {:noreply, state}
  end

  def handle_info(msg, state) do
    {:noreply, state}
  end

  def handle_recovery(recovered, state) do
    state = super(recovered, state)

    for {_, msg} <- state.buffer do
      :syn.publish({state.instance.pid, :flow_out, state.id}, {msg, state.id})
    end

    state
  end

  defp save_state(state, sync_ids) do
    BPEXE.Proc.Instance.save_state(state.instance, state.id, self(), %{buffer: state.buffer})
    BPEXE.Proc.Instance.commit_state(state.instance, [state.id, state.process_id] ++ sync_ids)
  end
end
