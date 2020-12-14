defmodule BPEXE.Proc.Process.Log do
  defmodule FlowNodeActivated do
    defstruct pid: nil, id: nil, token: nil, message: nil
  end

  defmodule FlowNodeForward do
    defstruct pid: nil, id: nil, token: nil, to: []
  end

  defmodule EventBasedGatewayActivated do
    defstruct pid: nil, id: nil, token: nil
  end

  defmodule EventBasedGatewayCompleted do
    defstruct pid: nil, id: nil, token: nil, to: []
  end

  defmodule ParallelGatewayReceived do
    defstruct pid: nil, id: nil, token: nil, from: nil
  end

  defmodule ParallelGatewayCompleted do
    defstruct pid: nil, id: nil, token: nil, to: []
  end

  defmodule EventActivated do
    defstruct pid: nil, id: nil, token: nil
  end

  defmodule EventTrigerred do
    defstruct pid: nil, id: nil, token: nil
  end

  defmodule EventCompleted do
    defstruct pid: nil, id: nil, token: nil
  end

  defmodule SequenceFlowStarted do
    defstruct pid: nil, id: nil, token: nil
  end

  defmodule SequenceFlowCompleted do
    defstruct pid: nil, id: nil, token: nil
  end

  defmodule TaskActivated do
    defstruct pid: nil, id: nil, token: nil
  end

  defmodule TaskCompleted do
    defstruct pid: nil, id: nil, token: nil
  end
end
