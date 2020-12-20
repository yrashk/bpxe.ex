defmodule BPXE.Engine.FlowHandler do
  @callback save_state(
              blueprint :: term,
              txn :: term,
              blueprint_id :: term,
              id :: term,
              pid :: pid,
              state :: term,
              handler_config :: term
            ) ::
              :ok | {:error, :term}
  @callback commit_state(
              blueprint :: term,
              txn :: term,
              blueprint_id :: term,
              id :: term,
              handler_config :: term
            ) ::
              :ok | {:error, :term}

  @callback restore_state(blueprint :: term, blueprint_id :: term, handler_config :: term) ::
              :ok | {:error, :term}
  @optional_callbacks restore_state: 3
end
