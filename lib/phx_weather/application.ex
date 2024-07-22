defmodule PhxWeather.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      PhxWeatherWeb.Telemetry,
      {Phoenix.PubSub, name: PhxWeather.PubSub},
      {Cluster.Supervisor, [topologies, [name: PhxWeather.ClusterSupervisor]]},
      {Horde.DynamicSupervisor,
       [
         name: PhxWeather.WeatherSupervisor,
         members: :auto,
         strategy: :one_for_one
       ]},
      {Horde.Registry,
       [
         keys: :unique,
         name: PhxWeather.WeatherRegistry,
         members: :auto
       ]},
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
