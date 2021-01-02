defmodule BPXE.Registry do
  @moduledoc """
  BPXE.Registry provides centralized abstraction for a name registry.

  At the moment, it follows `syn`'s API closely but this might change in the future.

  To list used names, run `mix bpxe.registry`
  """

  @type name :: any()

  @spec register(name) :: :ok | {:error, :taken}
  def register(name) do
    register(name, nil)
  end

  @spec register(name, any()) :: :ok | {:error, :taken}
  def register(name, meta) when not is_pid(meta) do
    register(name, self(), meta)
  end

  @spec register(name, pid()) :: :ok | {:error, :taken}
  def register(name, pid) when is_pid(pid) do
    register(name, pid, nil)
  end

  @spec register(name, pid(), any()) :: :ok | {:error, :taken}
  def register(name, pid, meta) do
    :syn.register(name, pid, meta)
  end

  @spec unregister(name) :: :ok | {:error, :undefined}
  def unregister(name) do
    :syn.unregister(name)
  end

  @spec whereis(name) :: nil | pid()
  @spec whereis(name, meta: false) :: nil | pid()
  @spec whereis(name, meta: true) :: nil | {pid(), any()}
  def whereis(name, options \\ []) do
    if options[:meta] do
      case :syn.whereis(name, :with_meta) do
        :undefined -> nil
        {pid, meta} -> {pid, meta}
      end
    else
      case :syn.whereis(name) do
        :undefined -> nil
        pid -> pid
      end
    end
  end
end
