defmodule BPXE.Engine.Process.Log do
  defmodule NewProcessActivation do
    defstruct pid: nil, id: nil, activation: nil
  end

  defmodule FlowNodeActivated do
    defstruct pid: nil, id: nil, token_id: nil, token: nil
  end

  defmodule FlowNodeForward do
    defstruct pid: nil, id: nil, token_id: nil, to: []
  end

  defmodule ExpressionErrorOccurred do
    defstruct pid: nil, id: nil, token_id: nil, expression: nil, error: nil
  end

  defmodule ExclusiveGatewayActivated do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule EventBasedGatewayActivated do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule EventBasedGatewayCompleted do
    defstruct pid: nil, id: nil, token_id: nil, to: []
  end

  defmodule ParallelGatewayReceived do
    defstruct pid: nil, id: nil, token_id: nil, from: nil
  end

  defmodule ParallelGatewayCompleted do
    defstruct pid: nil, id: nil, token_id: nil, to: []
  end

  defmodule InclusiveGatewayReceived do
    defstruct pid: nil, id: nil, token_id: nil, from: nil
  end

  defmodule InclusiveGatewayCompleted do
    defstruct pid: nil, id: nil, token_id: nil, fired: []
  end

  defmodule PrecedenceGatewayActivated do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule PrecedenceGatewayPrecedenceEstablished do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule PrecedenceGatewayTokenDiscarded do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule SensorGatewayActivated do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule SensorGatewayCompleted do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule EventActivated do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule EventTrigerred do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule EventCompleted do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule SequenceFlowStarted do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule SequenceFlowCompleted do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule TaskActivated do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule TaskCompleted do
    defstruct pid: nil, id: nil, token_id: nil
  end

  defmodule ScriptTaskErrorOccurred do
    defstruct pid: nil, id: nil, token_id: nil, error: nil
  end
end
