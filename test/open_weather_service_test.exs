defmodule OpenWeatherServiceTest do
  use PhxWeatherWeb.ConnCase
  alias PhxWeather

  alias PhxWeather.WeatherData
  alias PhxWeather.OpenWeatherService

  describe "get_geocoded_location/1" do
    test "works given valid data" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, [%{lat: 10, lon: -10, state: "IL", country: "US"}])
      end)

      assert {:ok, %{lat: 10, lon: -10, state: "IL", country: "US"}} =
               OpenWeatherService.geocode_location("Chicago,IL,US")
    end

    test "when more than one location is returned, the first in the list is used" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(
          conn,
          [
            %{lat: 100, lon: 200, state: "WI", country: "US"},
            %{lat: 10, lon: 20, state: "IL", country: "US"}
          ]
        )
      end)

      assert {:ok, %{lat: 100, lon: 200, state: "WI", country: "US"}} =
               OpenWeatherService.geocode_location("Madison,WI,US")
    end

    test "non-existant location is handled gracefully" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, [])
      end)

      location = "Chicago,IL,US"

      assert {:error, :unknown_location, ^location} =
               OpenWeatherService.geocode_location(location)
    end

    test "geocoder request failure is handled gracefully" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        resp(conn, 500, "")
      end)

      assert {:error, :geocoder_failure, %Req.Response{}} =
               OpenWeatherService.geocode_location("Chicago, IL, US")
    end
  end

  describe "get_weather_data/2" do
    test "successful retrieval is correctly parsed" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(
          conn,
          %{
            id: 100,
            dt: System.os_time(:second),
            name: "Erewhon",
            main: %{
              temp: 74,
              feels_like: 75,
              temp_max: 95,
              temp_min: 60,
              humidity: 66,
              pressure: 1101
            },
            weather: [
              %{
                description: "Clear",
                icon: "10d"
              },
              %{
                description: "Cloudy",
                icon: "12n"
              }
            ]
          }
        )
      end)

      assert {:ok, %WeatherData{} = weather_data} =
               OpenWeatherService.get_weather_data(100, -100)

      assert "Erewhon" == weather_data.name
      assert 100 == weather_data.id
      assert 74 == weather_data.curr_temp
      assert 75 == weather_data.feels_like
      assert 95 == weather_data.projected_high
      assert 60 == weather_data.projected_low
      assert 66 == weather_data.humidity
      assert 1101 == weather_data.barometric_pressure
      assert "Clear" == weather_data.current_conditions
      assert "10d" == weather_data.current_conditions_icon
    end

    test "failed retrieval is handled gracefully" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        resp(conn, 500, "")
      end)

      assert {:error, :weather_data_retrieval, _} =
               OpenWeatherService.get_weather_data(100, -100)
    end
  end
end
