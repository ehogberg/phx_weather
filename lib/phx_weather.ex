defmodule PhxWeather do
  @moduledoc """
  PhxWeather keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias PhxWeather.WeatherData
  alias PhxWeather.OpenWeatherService

  def retrieve_weather(name) when is_binary(name) do
    with {:ok, %{lat: _lat, lon: _lon} = geocode} <- OpenWeatherService.geocode_location(name),
         {:ok, %WeatherData{}} = weather_data <- retrieve_weather(geocode) do
      weather_data
    end
  end

  def retrieve_weather(%{lat: lat, lon: lon} = geocode) do
    case WeatherData.get_weather(lat, lon) do
      {:ok, %WeatherData{} = weather_data} ->
        {
          :ok,
          weather_data
          |> Map.put(:lat, lat)
          |> Map.put(:lon, lon)
          |> Map.put(:state, geocode[:state])
          |> Map.put(:country, geocode[:country])
        }

      error ->
        error
    end
  end

  def geocode_location_list(locations) do
    locations
    |> Enum.map(&geocode_location/1)
    |> Enum.split_with(fn
      {:ok, _} -> true
      _ -> false
    end)
  end

  def geocode_location(location),
    do: OpenWeatherService.geocode_location(location)
end
