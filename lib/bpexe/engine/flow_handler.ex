defmodule BPEXE.Engine.FlowHandler do
  @callback save_state(
              instance :: term,
              txn :: term,
              instance_id :: term,
              id :: term,
              pid :: pid,
              state :: term,
              handler_config :: term
            ) ::
              :ok | {:error, :term}
  @callback commit_state(
              instance :: term,
              txn :: term,
              instance_id :: term,
              id :: term,
              handler_config :: term
            ) ::
              :ok | {:error, :term}

  @callback restore_state(instance :: term, instance_id :: term, handler_config :: term) ::
              :ok | {:error, :term}
  @optional_callbacks restore_state: 3
end
