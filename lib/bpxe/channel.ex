defmodule BPXE.Channel do
  @moduledoc """
  BPXE.Channel provides basic functionality similar to pub/sub. A process can join a channel
  and start receiving messages and calls, and can leave a channel.

  At the moment, it follows `syn`'s API closely but this might change in the future.

  To list used channels, run `mix bpxe.channel.list`
  """

  @type group :: any()
  @type intended_recipient_count :: non_neg_integer()
  @type reply :: any()
  @type replies :: [{pid(), reply()}]
  @type bad_pids :: [pid()]

  @spec join(group) :: :ok
  @spec join(group, pid()) :: :ok
  def join(name, pid \\ self()) do
    :syn.join(name, pid)
  end

  @spec leave(group) :: :ok | {:error, :not_in_group}
  @spec leave(group, pid()) :: :ok | {:error, :not_in_group}
  def(leave(name, pid \\ self())) do
    :syn.leave(name, pid)
  end

  @spec publish(group, any()) :: {:ok, intended_recipient_count}
  def publish(name, message) do
    :syn.publish(name, message)
  end

  @spec multi_call(group, any()) :: {replies, bad_pids}
  @spec multi_call(group, any(), timeout) :: {replies, bad_pids}
  def multi_call(name, message, timeout \\ 5000) do
    :syn.multi_call(name, message, timeout)
  end

  @spec multi_call_reply(pid(), any()) :: :ok
  def multi_call_reply(pid, reply) do
    :syn.multi_call_reply(pid, reply)
  end

  @spec get_members(group) :: [pid()]
  def get_members(name) do
    :syn.get_members(name)
  end

  defmacro multi_call, do: :syn_multi_call
end
