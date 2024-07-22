defmodule PhxWeatherWeb.WeatherLive.ShowLocation do
  use PhxWeatherWeb, :live_component
  alias Phoenix.LiveView.AsyncResult
  alias PhxWeather
  require Logger

  @impl true
  def update(%{weather_data: weather_data}, socket) when weather_data != nil do
    {
      :ok,
      assign(socket, :weather_data, AsyncResult.ok(weather_data))
    }
  end

  @impl true
  def update(assigns, socket) do
    parent_pid = self()

    {
      :ok,
      socket
      |> assign(assigns)
      |> assign_async(
        :weather_data,
        fn -> fetch_weather_data(assigns.location, assigns.id, parent_pid) end
      )
    }
  end

  defp fetch_weather_data(location, component_id, parent_pid) do
    case PhxWeather.retrieve_weather(location) do
      {:ok, weather_data} ->
        send_weather_data_id_to_parent(component_id, weather_data.id, parent_pid)
        {:ok, %{weather_data: weather_data}}

      error ->
        error
    end
  end

  defp send_weather_data_id_to_parent(component_id, weather_data_id, parent_pid) do
    Logger.debug("Sending weather data ID (ID: #{weather_data_id}, component #{component_id})")
    send(parent_pid, {:weather_data_id, {component_id, weather_data_id}})
  end

  attr :icon, :string, required: true
  attr :class, :string, default: nil
  def weather_icon(assigns) do
    ~H"""
    <img class={@class} src={"https://openweathermap.org/img/wn/#{@icon}.png"} />
    """
  end
end
