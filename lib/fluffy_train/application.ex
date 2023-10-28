defmodule FluffyTrain.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      FluffyTrainWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: FluffyTrain.PubSub},
      # Start Finch
      {Finch, name: FluffyTrain.Finch},
      # Start the Endpoint (http/https)
      FluffyTrainWeb.Endpoint,
      FluffyTrain.OpenEL,
      ExUnit.Server,
      ExUnit.CaptureServer,
      ExUnit.OnExitHandler
      # Start a worker by calling: FluffyTrain.Worker.start_link(arg)
      # {FluffyTrain.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FluffyTrain.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FluffyTrainWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
