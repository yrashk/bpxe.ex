defmodule BPEXE.Proc.SequenceFlow do
  use GenServer
  alias BPEXE.Proc.Process
  alias BPEXE.Proc.Process.Log

  defstruct id: nil, options: %{}, instance: nil, process: nil

  def start_link(id, options, instance, process) do
    # This way we can wait until it is initialized
    :proc_lib.start_link(__MODULE__, :init, [{id, options, instance, process}])
  end

  def init({id, options, instance, process}) do
    :syn.join({instance, :flow_in, id}, self())
    # Done initializing
    :proc_lib.init_ack({:ok, self()})

    :gen_server.enter_loop(__MODULE__, [], %__MODULE__{
      id: id,
      options: options,
      instance: instance,
      process: process
    })
  end

  def handle_info({%BPEXE.Message{token: token} = msg, id}, state) do
    Process.log(state.process, %Log.SequenceFlowStarted{pid: self(), id: state.id, token: token})
    :syn.publish({state.instance, :flow_out, id}, {msg, id})

    Process.log(state.process, %Log.SequenceFlowCompleted{
      pid: self(),
      id: state.id,
      token: token
    })

    {:noreply, state}
  end

  def handle_info(msg, state) do
    {:noreply, state}
  end
end
