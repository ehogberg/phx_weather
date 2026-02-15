defmodule PhxWeather.WeatherData do
  @moduledoc """
  GenServer for managing weather data for a specific location.

  Spawned on-demand when a location is requested and automatically terminates
  after 2 minutes of client inactivity. Polls OpenWeather API every 60 seconds
  and broadcasts updates via PubSub.
  """

  use GenServer
  alias PhxWeather.OpenWeatherService
  alias Phoenix.PubSub
  require Logger

  # 2 minutes
  @acknowledgement_timeout 60 * 2
  @max_retry_attempts 3
  # 1 second
  @initial_retry_delay 1_000

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
        weather_data: nil,
        weather_data_id: nil,
        lat: lat,
        lon: lon,
        timer: nil,
        last_acknowledged_at: DateTime.utc_now(),
        retry_count: 0,
        consecutive_failures: 0
      },
      {:continue, :load_weather_data}
    }
  end

  @impl true
  def handle_continue(:load_weather_data, %{lat: lat, lon: lon, retry_count: retry_count} = state) do
    case OpenWeatherService.get_weather_data(lat, lon) do
      {:ok, weather} ->
        :telemetry.execute(
          [:phx_weather, :weather_data, :initialized],
          %{count: 1},
          %{lat: lat, lon: lon, weather_id: weather.id}
        )

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
            | weather_data: weather,
              weather_data_id: weather.id,
              timer: Process.send_after(self(), :reload_weather_data, 60_000),
              retry_count: 0,
              consecutive_failures: 0
          }
        }

      error ->
        Logger.warning(
          "Failed to initialize weather data for location #{lat},#{lon}: #{inspect(error)}"
        )

        :telemetry.execute(
          [:phx_weather, :weather_data, :init_failed],
          %{count: 1},
          %{lat: lat, lon: lon, retry_count: retry_count, error: error}
        )

        if retry_count < @max_retry_attempts do
          # Exponential backoff: 1s, 2s, 4s
          delay = (@initial_retry_delay * :math.pow(2, retry_count)) |> trunc()

          Logger.info(
            "Retrying weather data fetch for #{lat},#{lon} in #{delay}ms (attempt #{retry_count + 1}/#{@max_retry_attempts})"
          )

          Process.send_after(self(), :retry_load_weather_data, delay)

          {
            :noreply,
            %{state | retry_count: retry_count + 1}
          }
        else
          Logger.error(
            "Failed to initialize weather data for #{lat},#{lon} after #{@max_retry_attempts} attempts, stopping GenServer"
          )

          {:stop, {:initialization_failed, error}, state}
        end
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
      if state.weather_data == nil do
        {:error, :no_weather_data_retrieved}
      else
        state.weather_data
      end

    {
      :reply,
      {:ok, resp},
      %{state | last_acknowledged_at: DateTime.utc_now()}
    }
  end

  @impl true
  def handle_info(:retry_load_weather_data, state) do
    handle_continue(:load_weather_data, state)
  end

  @impl true
  def handle_info(
        :reload_weather_data,
        %{
          lat: _lat,
          lon: _lon,
          weather_data_id: weather_data_id,
          last_acknowledged_at: last_acknowledged_at
        } = state
      ) do
    Logger.debug(
      "Checking to see if any instance is still using weather data for id #{weather_data_id}"
    )

    Logger.debug(
      "Current time: #{DateTime.utc_now()}, expiry: #{DateTime.add(last_acknowledged_at, @acknowledgement_timeout)}"
    )

    if DateTime.after?(
         DateTime.utc_now(),
         DateTime.add(last_acknowledged_at, @acknowledgement_timeout)
       ) do
      Logger.info("Shutting down weather data #{weather_data_id} due to client inactivity.")

      :telemetry.execute(
        [:phx_weather, :weather_data, :terminated],
        %{count: 1},
        %{weather_id: weather_data_id, reason: :client_timeout}
      )

      {:stop, {:shutdown, {:client_timeout, weather_data_id}}, state}
    else
      Logger.debug("Checking for updates to weather data (ID #{weather_data_id})")
      reload_and_publish_weather_data(state)
    end
  end

  @impl true
  def handle_info(:publish_weather_data_update, state) do
    Logger.debug("Notifying pub/sub of update to weather data id #{state.weather_data_id}")

    PubSub.broadcast(
      PhxWeather.PubSub,
      "weather_data:#{state.weather_data_id}",
      {:weather_data_updated, %{id: state.weather_data_id, weather_data: state.weather_data}}
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

  defp reload_and_publish_weather_data(state) do
    case OpenWeatherService.get_weather_data(state.lat, state.lon) do
      {:ok, %__MODULE__{} = latest_weather} ->
        :telemetry.execute(
          [:phx_weather, :weather_data, :api_call],
          %{count: 1},
          %{lat: state.lat, lon: state.lon, status: :success}
        )

        consecutive_failures = 0

        weather_data =
          if state.weather_data.data_updated_at != latest_weather.data_updated_at do
            Process.send_after(self(), :publish_weather_data_update, 1_000)
            latest_weather
          else
            state.weather_data
          end

        {
          :noreply,
          %{
            state
            | weather_data: weather_data,
              timer: Process.send_after(self(), :reload_weather_data, 60_000),
              consecutive_failures: consecutive_failures
          }
        }

      error ->
        consecutive_failures = state.consecutive_failures + 1

        Logger.warning(
          "Failed to reload weather data for #{state.lat},#{state.lon} " <>
            "(consecutive failures: #{consecutive_failures}): #{inspect(error)}"
        )

        :telemetry.execute(
          [:phx_weather, :weather_data, :api_call],
          %{count: 1},
          %{
            lat: state.lat,
            lon: state.lon,
            status: :failure,
            consecutive_failures: consecutive_failures
          }
        )

        # Alert on multiple consecutive failures
        if consecutive_failures >= 5 do
          Logger.error(
            "Weather data for #{state.lat},#{state.lon} has failed #{consecutive_failures} times consecutively. " <>
              "Consider checking API connectivity or rate limits."
          )
        end

        # Continue with stale data
        {
          :noreply,
          %{
            state
            | timer: Process.send_after(self(), :reload_weather_data, 60_000),
              consecutive_failures: consecutive_failures
          }
        }
    end
  end
end
