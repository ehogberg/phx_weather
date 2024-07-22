defmodule PhxWeather.OpenWeatherService do
  @moduledoc false

  @openweather_base_api_path "https://api.openweathermap.org"
  @openweather_data_api_path "/data/2.5/weather"
  @openweather_geocode_api_path "/geo/1.0/direct"

  alias PhxWeather.WeatherData

  def geocode_location(location_name) do
    (%{status: status, body: body} = resp) =
      @openweather_geocode_api_path
      |> openweather_api_request(q: location_name)
      |> Req.get!(url: @openweather_geocode_api_path)

    case status do
      200 -> get_lat_lon_for_station_if_found(body, location_name)
      _ -> {:error, :geocoder_failure, resp}
    end
  end

  defp get_lat_lon_for_station_if_found([], location_name),
    do: {:error, :unknown_location, location_name}

  defp get_lat_lon_for_station_if_found(body, _) do
    body = hd(body)

    {
      :ok,
      %{
        lat: body[:lat],
        lon: body[:lon],
        state: body[:state],
        country: body[:country]
      }
    }
  end

  def get_weather_data(lat, lon) do
    (%{status: status, body: body} = resp) =
      @openweather_data_api_path
      |> openweather_api_request(lat: lat, lon: lon, units: "imperial")
      |> Req.get!()

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
        country: resp_body[:sys][:country],
        retrieved_at: DateTime.utc_now(),
        data_updated_at: DateTime.from_unix!(resp_body[:dt]),
        name: resp_body[:name],
        curr_temp: trunc(resp_body[:main][:temp]),
        feels_like: trunc(resp_body[:main][:feels_like]),
        projected_high: trunc(resp_body[:main][:temp_max]),
        projected_low: trunc(resp_body[:main][:temp_min]),
        humidity: resp_body[:main][:humidity],
        barometric_pressure: resp_body[:main][:pressure],
        current_conditions: curr_weather[:description],
        current_conditions_icon: curr_weather[:icon]
      }
    }
  end

  defp openweather_api_request(url, params) do
    params = Keyword.put_new(params, :appid, openweather_app_id())

    [
      base_url: @openweather_base_api_path,
      url: url,
      params: params,
      decode_json: [keys: :atoms]
    ]
    |> Keyword.merge(Application.get_env(:phx_weather, :openweather_req_options, []))
    |> Req.new()
  end

  defp openweather_app_id(),
    do: Application.fetch_env!(:phx_weather, :openweather_api_key)
end
