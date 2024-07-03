defmodule PhxWeather.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PhxWeatherWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:phx_weather, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PhxWeather.PubSub},
      # Start a worker by calling: PhxWeather.Worker.start_link(arg)
      # {PhxWeather.Worker, arg},
      # Start to serve requests, typically the last entry
      PhxWeatherWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PhxWeather.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PhxWeatherWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
