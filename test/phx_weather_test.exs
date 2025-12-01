defmodule PhxWeatherTest do
  use PhxWeatherWeb.ConnCase, async: false

  alias PhxWeather
  alias PhxWeather.WeatherData

  setup do
    # Start required services
    start_supervised!({Phoenix.PubSub, name: PhxWeather.PubSub})

    start_supervised!(
      {Horde.DynamicSupervisor,
       [name: PhxWeather.WeatherSupervisor, strategy: :one_for_one, members: :auto]}
    )

    start_supervised!(
      {Horde.Registry, [keys: :unique, name: PhxWeather.WeatherRegistry, members: :auto]}
    )

    :ok
  end

  describe "retrieve_weather/1 with location name" do
    test "successfully retrieves weather for a valid location name" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        cond do
          String.contains?(conn.request_path, "/geo/") ->
            Req.Test.json(conn, [
              %{lat: 41.85, lon: -87.65, state: "IL", country: "US"}
            ])

          String.contains?(conn.request_path, "/data/") ->
            Req.Test.json(conn, valid_weather_response())

          true ->
            Plug.Conn.resp(conn, 404, "Not found")
        end
      end)

      assert {:ok, %WeatherData{} = weather} = PhxWeather.retrieve_weather("Chicago")
      assert weather.name == "Chicago"
      assert weather.lat == 41.85
      assert weather.lon == -87.65
      assert weather.state == "IL"
      assert weather.country == "US"
    end

    test "returns error for unknown location" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        if String.contains?(conn.request_path, "/geo/") do
          Req.Test.json(conn, [])
        else
          Plug.Conn.resp(conn, 404, "Not found")
        end
      end)

      result = PhxWeather.retrieve_weather("NonexistentCity12345")
      assert {:error, :unknown_location, "NonexistentCity12345"} = result
    end

    test "returns error when geocoding API fails" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Plug.Conn.resp(conn, 500, "Service unavailable")
      end)

      result = PhxWeather.retrieve_weather("Chicago")
      assert {:error, :geocoder_failure, _} = result
    end
  end

  describe "retrieve_weather/1 with geocode map" do
    test "successfully retrieves weather for geocode coordinates" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      geocode = %{lat: 41.85, lon: -87.65, state: "IL", country: "US"}

      assert {:ok, %WeatherData{} = weather} = PhxWeather.retrieve_weather(geocode)
      assert weather.name == "Chicago"
      assert weather.lat == 41.85
      assert weather.lon == -87.65
      assert weather.state == "IL"
      assert weather.country == "US"
    end

    test "returns error when weather data cannot be retrieved" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Plug.Conn.resp(conn, 500, "Service unavailable")
      end)

      geocode = %{lat: 41.85, lon: -87.65, state: "IL", country: "US"}

      # Due to retry logic, this will take a few seconds
      result = PhxWeather.retrieve_weather(geocode)

      # Should eventually fail after retries
      assert match?({:error, _}, result)
    end

    test "merges geocode data into weather data" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      geocode = %{lat: 41.85, lon: -87.65, state: "IL", country: "US"}

      assert {:ok, weather} = PhxWeather.retrieve_weather(geocode)
      assert weather.lat == geocode.lat
      assert weather.lon == geocode.lon
      assert weather.state == geocode.state
      assert weather.country == geocode.country
    end
  end

  describe "geocode_location/1" do
    test "successfully geocodes a location" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, [
          %{lat: 41.85, lon: -87.65, state: "IL", country: "US"}
        ])
      end)

      assert {:ok, %{lat: 41.85, lon: -87.65, state: "IL", country: "US"}} =
               PhxWeather.geocode_location("Chicago")
    end

    test "returns error for unknown location" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, [])
      end)

      assert {:error, :unknown_location, "UnknownPlace"} =
               PhxWeather.geocode_location("UnknownPlace")
    end

    test "uses first result when multiple locations match" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, [
          %{lat: 41.85, lon: -87.65, state: "IL", country: "US"},
          %{lat: 42.0, lon: -88.0, state: "WI", country: "US"}
        ])
      end)

      assert {:ok, %{lat: 41.85, lon: -87.65}} = PhxWeather.geocode_location("Springfield")
    end
  end

  describe "geocode_location_list/1" do
    test "splits valid and invalid locations" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        location = conn.params["q"]

        cond do
          location == "Chicago" ->
            Req.Test.json(conn, [
              %{lat: 41.85, lon: -87.65, state: "IL", country: "US"}
            ])

          location == "London" ->
            Req.Test.json(conn, [
              %{lat: 51.51, lon: -0.13, state: nil, country: "GB"}
            ])

          location == "InvalidCity" ->
            Req.Test.json(conn, [])

          true ->
            Req.Test.json(conn, [])
        end
      end)

      {valid, invalid} =
        PhxWeather.geocode_location_list(["Chicago", "London", "InvalidCity"])

      assert length(valid) == 2
      assert length(invalid) == 1

      assert Enum.all?(valid, fn result -> match?({:ok, _}, result) end)
      assert Enum.all?(invalid, fn result -> match?({:error, _, _}, result) end)
    end

    test "handles all valid locations" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, [
          %{lat: 0.0, lon: 0.0, state: nil, country: "XX"}
        ])
      end)

      {valid, invalid} = PhxWeather.geocode_location_list(["City1", "City2", "City3"])

      assert length(valid) == 3
      assert length(invalid) == 0
    end

    test "handles all invalid locations" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, [])
      end)

      {valid, invalid} = PhxWeather.geocode_location_list(["Bad1", "Bad2"])

      assert length(valid) == 0
      assert length(invalid) == 2
    end

    test "handles empty list" do
      {valid, invalid} = PhxWeather.geocode_location_list([])

      assert valid == []
      assert invalid == []
    end
  end

  # Helper functions

  defp valid_weather_response do
    %{
      id: 4887398,
      dt: System.os_time(:second),
      name: "Chicago",
      sys: %{country: "US"},
      main: %{
        temp: 74,
        feels_like: 75,
        temp_max: 80,
        temp_min: 68,
        humidity: 65,
        pressure: 1013
      },
      weather: [
        %{
          description: "clear sky",
          icon: "01d"
        }
      ]
    }
  end
end
