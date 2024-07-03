defmodule PhxWeather do
  @moduledoc """
  PhxWeather keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias PhxWeather.WeatherData

  @openweather_base_api_path  "https://api.openweathermap.org"
  @openweather_data_api_path "#{@openweather_base_api_path}/data/2.5/weather"
  @openweather_geocode_api_path "#{@openweather_base_api_path}/geo/1.0/direct"

  def retrieve_weather(name) when is_binary(name) do
    with  {:ok, lat, lon, state, country}  <- get_geocoded_location(name),
          {:ok, %WeatherData{} = weather_data} <- retrieve_weather(lat, lon) do
        weather_data
        |> Map.put(:state, state)
        |> Map.put(:country, country)
    end
  end

  def retrieve_weather(lat, lon) when is_float(lat) and is_float(lon) do
    (%{status: status, body: body} = resp) = Req.get!(
      @openweather_data_api_path,
      [
        params: [lat: lat, lon: lon, units: "imperial", appid: openweather_app_id()],
        decode_json: [keys: :atoms]
      ]
    )

    case status do
      200 -> extract_weather_data(body)
      _ -> {:error, :weather_data_retrieval, resp}
    end
  end

  defp extract_weather_data(resp_body) do
    curr_weather = resp_body[:weather] |> hd()
    {
      :ok,
      %WeatherData{
        id: resp_body[:id],
        retrieved_at: DateTime.utc_now(),
        data_updated_at: DateTime.from_unix!(resp_body[:dt]),
        name: resp_body[:name],
        curr_temp: resp_body[:main][:temp],
        feels_like: resp_body[:main][:feels_like],
        projected_high: resp_body[:main][:temp_max],
        projected_low: resp_body[:main][:temp_min],
        humidity: resp_body[:main][:humidity],
        barometric_pressure: resp_body[:main][:pressure],
        current_conditions: curr_weather[:description],
        current_conditions_icon: curr_weather[:icon]
      }
    }

  end

  defp get_geocoded_location(location_name) do
    (%{status: status, body: body} = resp) = Req.get!(
      @openweather_geocode_api_path,
      [
        params: [q: location_name, appid: openweather_app_id()],
        decode_json: [keys: :atoms]
      ])

    case status do
      200 -> get_lat_lon_for_station_if_found(body,location_name)
      _ -> {:error, :geocoder_failure, resp}
    end
   end

  defp get_lat_lon_for_station_if_found([], location_name),
    do: {:error, :unknown_location, location_name}

  defp get_lat_lon_for_station_if_found(body, _) do
    body = hd(body)
    {:ok, body[:lat], body[:lon], body[:state], body[:country] }
  end

  defp openweather_app_id(),
    do: Application.fetch_env!(:phx_weather, :openweather_api_key)
end
