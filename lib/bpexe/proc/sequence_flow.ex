defmodule BPEXE.Proc.SequenceFlow do
  use GenServer

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

  def handle_info({%BPEXE.Message{} = msg, id}, state) do
    :syn.publish({state.instance, :flow_out, id}, {msg, id})
    {:noreply, state}
  end

  def handle_info(msg, state) do
    {:noreply, state}
  end
end
