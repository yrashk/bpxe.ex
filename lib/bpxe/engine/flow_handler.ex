defmodule BPXE.Engine.FlowHandler do
  @callback save_state(
              model :: term,
              generation :: term,
              model_id :: term,
              id :: term,
              pid :: pid,
              state :: term,
              handler_config :: term
            ) ::
              :ok | {:error, :term}
  @callback commit_state(
              model :: term,
              generation :: term,
              model_id :: term,
              id :: term,
              handler_config :: term
            ) ::
              :ok | {:error, :term}

  @callback restore_state(model :: term, model_id :: term, handler_config :: term) ::
              :ok | {:error, :term}
  @optional_callbacks restore_state: 3
end
