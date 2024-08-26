defmodule PhxWeather.WeatherData do
  @moduledoc false

  use GenServer
  alias PhxWeather.OpenWeatherService
  alias Phoenix.PubSub
  require Logger

  @acknowledgement_timeout 1000 * 60 * 30  # 30 minutes

  defstruct [
    :id,
    :lat,
    :lon,
    :name,
    :state,
    :country,
    :curr_temp,
    :feels_like,
    :projected_high,
    :projected_low,
    :humidity,
    :barometric_pressure,
    :current_conditions,
    :current_conditions_icon,
    :retrieved_at,
    :data_updated_at
  ]

  def start_link(args) do
    lat = Keyword.fetch!(args, :lat)
    lon = Keyword.fetch!(args, :lon)

    GenServer.start_link(
      __MODULE__,
      args,
      name: {:via, Horde.Registry, {PhxWeather.WeatherRegistry, {lat, lon}}}
    )
  end

  def get_weather(lat, lon) do
    server_proc = Horde.Registry.lookup(PhxWeather.WeatherRegistry, {lat, lon})

    if server_proc == [] do
      Horde.DynamicSupervisor.start_child(
        PhxWeather.WeatherSupervisor,
        {__MODULE__, [lat: lat, lon: lon]}
      )
    end

    GenServer.call(
      {:via, Horde.Registry, {PhxWeather.WeatherRegistry, {lat, lon}}},
      :get_weather
    )
  end

  def location(name_or_pid) do
    GenServer.call(name_or_pid, :location)
  end

  # GenServer impl below
  @impl true
  def init(attrs) do
    lat = Keyword.get(attrs, :lat)
    lon = Keyword.get(attrs, :lon)

    {
      :ok,
      %{
        weather_data: [],
        weather_data_id: nil,
        lat: lat,
        lon: lon,
        timer: nil,
        last_acknowledged_at: DateTime.utc_now()
      },
      {:continue, :load_weather_data}
    }
  end

  @impl true
  def handle_continue(:load_weather_data, %{lat: lat, lon: lon} = state) do
    case OpenWeatherService.get_weather_data(lat, lon) do
      {:ok, weather} ->
        Phoenix.PubSub.broadcast(
            PhxWeather.PubSub,
            "weather_data_admin",
            {:location_added, %{lat: lat, lon: lon}}
        )

        Phoenix.PubSub.subscribe(
          PhxWeather.PubSub,
          "weather_data:#{weather.id}"
        )

        {
          :noreply,
          %{
            state
            | weather_data: [weather],
              weather_data_id: weather.id,
              timer: Process.send_after(self(), :reload_weather_data, 60_000)
          }
        }

      error ->
        {:stop, error}
    end
  end

  @impl true
  def handle_call(:location, _, state) do
    {
      :reply,
      %{
        lat: state.lat,
        lon: state.lon
      },
      state
    }
  end

  @impl true
  def handle_call(:get_weather, _, state) do
    resp =
      if state.weather_data == [] do
        {:error, :no_weather_data_retrieved}
      else
        hd(state.weather_data)
      end

    {
      :reply,
      {:ok, resp},
      %{state |
        last_acknowledged_at: DateTime.utc_now()
      }
    }
  end

  @impl true
  def handle_info(:reload_weather_data, state) do
    Logger.debug("Checking for updates to weather data (ID #{state.weather_data_id})")

    weather_data =
      case OpenWeatherService.get_weather_data(state.lat, state.lon) do
        {:ok, %__MODULE__{} = latest_weather} ->
          current_weather = hd(state.weather_data)

          if current_weather.data_updated_at != latest_weather.data_updated_at do
            Process.send_after(self(), :publish_weather_data_update, 1_000)
            [latest_weather | state.weather_data]
          else
            state.weather_data
          end

        _ ->
          state.weather_data
      end

    {
      :noreply,
      %{
        state
        | weather_data: weather_data,
          timer: Process.send_after(self(), :reload_weather_data, 60_000)
      }
    }
  end

  @impl true
  def handle_info(:publish_weather_data_update, state) do
    Logger.debug("Notifying pub/sub of update to weather data id #{state.weather_data_id}")

    PubSub.broadcast(
      PhxWeather.PubSub,
      "weather_data:#{state.weather_data_id}",
      {:weather_data_updated, %{id: state.weather_data_id, weather_data: hd(state.weather_data)}}
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:acknowledge_weather_data_update, weather_data_id}, state) do
    Logger.debug("Received acknowledgement of update for weather data #{weather_data_id}")

    {
      :noreply,
      %{state | last_acknowledged_at: DateTime.utc_now()}
    }
  end

  @impl true
  def handle_info(_evt, state) do
    {:noreply, state}
  end
end
