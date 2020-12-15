defmodule BPEXE.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: BPEXE.Worker.start_link(arg)
      # {BPEXE.Worker, arg}
      BPEXE.Proc.Instances
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BPEXE.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
