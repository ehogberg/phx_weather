defmodule PhxWeatherWeb.AdminLive do
  use PhxWeatherWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    {
      :ok,
      socket
    }
  end

  @impl true
  def handle_event("after_map_render", _, socket) do
    PhxWeatherWeb.Endpoint.subscribe("weather_data_admin")

    {
      :noreply,
      socket
      |> push_event(
        "initiate_weather_data",
        %{weather_stations: all_active_locations()})
    }
  end

  @impl true
  def handle_event(_evt, _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:location_added, %{lat: lat, lon: lon}}, socket) do
    {
      :noreply,
      socket
      |> push_event(
        "location_added",
        %{lat: lat, lon: lon}
      )
    }
  end

  def all_active_locations() do
    PhxWeather.WeatherSupervisor
    |> Horde.DynamicSupervisor.which_children()
    |> Enum.map(fn {_,pid,_,_} -> PhxWeather.WeatherData.location(pid) end)
    |> Enum.map(fn %{lat: lat, lon: lon} -> [lon, lat] end)
  end
end
