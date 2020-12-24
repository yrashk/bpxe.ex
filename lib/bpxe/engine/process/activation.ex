defmodule BPXE.Engine.Process.Activation do
  defstruct id: nil,
            model_id: nil,
            process_id: nil

  use ExConstructor
  alias :persistent_term, as: PT
  alias :atomics, as: Atomics

  def new(options \\ []) do
    activation = super(options)
    activation = %{activation | id: activation.id || generate_id()}
    PT.put({activation, :token_generation}, Atomics.new(1, signed: false))
    activation
  end

  def discard(%__MODULE__{} = activation) do
    PT.erase({activation, :token_generation})
    activation
  end

  def token_generation(%__MODULE__{} = activation) do
    PT.get({activation, :token_generation})
  end

  def next_token_generation(%__MODULE__{} = activation) do
    Atomics.add_get(token_generation(activation), 1, 1)
  end

  def reset_token_generation(%__MODULE__{} = activation) do
    a = Atomics.new(2, signed: false)
    PT.put({activation, :token_generation}, a)
  end

  def set_token_generation(%__MODULE__{} = activation, generation) do
    token_generation(activation)
    |> Atomics.put(1, generation)
  end

  defp generate_id() do
    {m, f, a} = Application.get_env(:bpxe, :activation_id_generator)
    apply(m, f, a)
  end
end
