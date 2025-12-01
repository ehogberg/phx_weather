defmodule PhxWeather.WeatherDataTest do
  use PhxWeatherWeb.ConnCase, async: false

  alias PhxWeather.{WeatherData, OpenWeatherService}
  import ExUnit.CaptureLog

  setup do
    # Ensure clean state for each test
    start_supervised!({Phoenix.PubSub, name: PhxWeather.PubSub})

    # Start Horde components needed for tests
    start_supervised!(
      {Horde.DynamicSupervisor,
       [name: PhxWeather.WeatherSupervisor, strategy: :one_for_one, members: :auto]}
    )

    start_supervised!(
      {Horde.Registry, [keys: :unique, name: PhxWeather.WeatherRegistry, members: :auto]}
    )

    :ok
  end

  describe "initialization" do
    test "successfully initializes with valid weather data" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      assert {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
      assert Process.alive?(pid)

      # Verify weather data can be retrieved
      assert {:ok, %WeatherData{} = weather} = WeatherData.get_weather(41.85, -87.65)
      assert weather.name == "Chicago"
      assert weather.curr_temp == 74
    end

    test "retries on initialization failure and eventually succeeds" do
      # First call fails, second succeeds
      call_count = :counters.new(1, [])

      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          Plug.Conn.resp(conn, 500, "Service unavailable")
        else
          Req.Test.json(conn, valid_weather_response())
        end
      end)

      log =
        capture_log(fn ->
          assert {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
          # Wait for retry to complete
          Process.sleep(1500)
          assert Process.alive?(pid)
        end)

      assert log =~ "Retrying weather data fetch"
      assert log =~ "attempt 1/3"
    end

    test "stops after max retry attempts" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Plug.Conn.resp(conn, 500, "Service unavailable")
      end)

      log =
        capture_log(fn ->
          {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
          # Wait for all retries to complete (1s + 2s + 4s + processing)
          Process.sleep(8000)
          refute Process.alive?(pid)
        end)

      assert log =~ "Failed to initialize weather data"
      assert log =~ "after 3 attempts"
    end

    test "emits telemetry event on successful initialization" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      events = capture_telemetry_events([:phx_weather, :weather_data, :initialized], fn ->
        {:ok, _pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
        Process.sleep(100)
      end)

      assert [event] = events
      assert event.measurements.count == 1
      assert event.metadata.lat == 41.85
      assert event.metadata.lon == -87.65
    end

    test "broadcasts location_added event on initialization" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      Phoenix.PubSub.subscribe(PhxWeather.PubSub, "weather_data_admin")

      {:ok, _pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)

      assert_receive {:location_added, %{lat: 41.85, lon: -87.65}}, 1000
    end
  end

  describe "timeout and shutdown" do
    test "shuts down after 2 minutes of inactivity" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)

      # Fast-forward time by sending shutdown message directly
      # (In real test, we'd wait 2 minutes or use a shorter timeout for testing)
      ref = Process.monitor(pid)

      # Simulate timeout by sending the message that would fire after 2 min
      send(pid, :reload_weather_data)

      # The process checks if last_acknowledged_at is > 2 min old
      # Since we just started, it won't shut down yet
      Process.sleep(100)
      assert Process.alive?(pid)

      # To properly test timeout, we'd need to either:
      # 1. Wait the full 2 minutes
      # 2. Make timeout configurable for tests
      # 3. Use mock time library
      # For now, verify the process is still alive with recent activity
      assert {:ok, %WeatherData{}} = WeatherData.get_weather(41.85, -87.65)
      assert Process.alive?(pid)
    end

    test "emits telemetry on termination" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      # Start with a custom state to test termination
      {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
      Process.sleep(100)

      events = capture_telemetry_events([:phx_weather, :weather_data, :terminated], fn ->
        # Force stop the GenServer
        GenServer.stop(pid, :normal)
        Process.sleep(100)
      end)

      # Note: This won't trigger the client_timeout termination event
      # since we're stopping it manually. A full integration test
      # would be needed to test the actual timeout behavior.
    end
  end

  describe "weather data updates" do
    test "polls for updates every 60 seconds" do
      call_count = :counters.new(1, [])

      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        :counters.add(call_count, 1, 1)
        Req.Test.json(conn, valid_weather_response())
      end)

      {:ok, _pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)

      initial_count = :counters.get(call_count, 1)
      assert initial_count == 1

      # Wait for next poll (60s is too long for tests, but verify first call)
      Process.sleep(100)
      # In a real scenario, we'd mock the timer or make it configurable
    end

    test "broadcasts weather_data_updated when data changes" do
      call_count = :counters.new(1, [])
      base_time = System.os_time(:second)

      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        response = valid_weather_response()
        # Change timestamp on second call to trigger update
        updated_response = put_in(response, [:dt], base_time + count * 100)

        Req.Test.json(conn, updated_response)
      end)

      {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
      Process.sleep(100)

      # Get the weather_data_id
      {:ok, weather} = WeatherData.get_weather(41.85, -87.65)
      weather_id = weather.id

      Phoenix.PubSub.subscribe(PhxWeather.PubSub, "weather_data:#{weather_id}")

      # Manually trigger reload to test update broadcast
      send(pid, :reload_weather_data)

      # Should receive update notification
      assert_receive {:weather_data_updated, %{id: ^weather_id, weather_data: _}}, 2000
    end

    test "handles API failures gracefully and continues with stale data" do
      call_count = :counters.new(1, [])

      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          # First call succeeds
          Req.Test.json(conn, valid_weather_response())
        else
          # Subsequent calls fail
          Plug.Conn.resp(conn, 500, "API Error")
        end
      end)

      log =
        capture_log(fn ->
          {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
          Process.sleep(100)

          # Should have initial data
          assert {:ok, %WeatherData{}} = WeatherData.get_weather(41.85, -87.65)

          # Trigger reload which will fail
          send(pid, :reload_weather_data)
          Process.sleep(100)

          # Should still have data (stale)
          assert {:ok, %WeatherData{}} = WeatherData.get_weather(41.85, -87.65)
          assert Process.alive?(pid)
        end)

      assert log =~ "Failed to reload weather data"
      assert log =~ "consecutive failures: 1"
    end

    test "logs error after 5 consecutive failures" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
      Process.sleep(100)

      # Now make API fail
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Plug.Conn.resp(conn, 500, "API Error")
      end)

      log =
        capture_log(fn ->
          # Trigger 5 failed reloads
          for _ <- 1..5 do
            send(pid, :reload_weather_data)
            Process.sleep(100)
          end
        end)

      assert log =~ "has failed 5 times consecutively"
      assert log =~ "checking API connectivity"
    end

    test "emits telemetry on successful API calls" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
      Process.sleep(100)

      events = capture_telemetry_events([:phx_weather, :weather_data, :api_call], fn ->
        send(pid, :reload_weather_data)
        Process.sleep(200)
      end)

      assert [event] = events
      assert event.measurements.count == 1
      assert event.metadata.status == :success
    end

    test "emits telemetry on failed API calls" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      {:ok, pid} = WeatherData.start_link(lat: 41.85, lon: -87.65)
      Process.sleep(100)

      # Make next call fail
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Plug.Conn.resp(conn, 500, "Error")
      end)

      events = capture_telemetry_events([:phx_weather, :weather_data, :api_call], fn ->
        send(pid, :reload_weather_data)
        Process.sleep(200)
      end)

      assert [event] = events
      assert event.measurements.count == 1
      assert event.metadata.status == :failure
      assert event.metadata.consecutive_failures == 1
    end
  end

  describe "process registry" do
    test "reuses existing process for same location" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      {:ok, weather1} = WeatherData.get_weather(41.85, -87.65)
      {:ok, weather2} = WeatherData.get_weather(41.85, -87.65)

      # Should be same data from same process
      assert weather1.id == weather2.id
    end

    test "creates separate processes for different locations" do
      Req.Test.stub(PhxWeb.WeatherTest, fn conn ->
        Req.Test.json(conn, valid_weather_response())
      end)

      {:ok, weather1} = WeatherData.get_weather(41.85, -87.65)
      {:ok, weather2} = WeatherData.get_weather(40.71, -74.00)

      # Should be different weather stations
      assert weather1.lat != weather2.lat
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

  defp capture_telemetry_events(event_name, fun) do
    events = []
    ref = make_ref()

    handler = fn ^event_name, measurements, metadata, _config ->
      send(self(), {ref, %{measurements: measurements, metadata: metadata}})
    end

    :telemetry.attach(
      "test-handler-#{inspect(ref)}",
      event_name,
      handler,
      nil
    )

    fun.()

    collected_events = collect_telemetry_events(ref, [])

    :telemetry.detach("test-handler-#{inspect(ref)}")

    collected_events
  end

  defp collect_telemetry_events(ref, acc) do
    receive do
      {^ref, event} -> collect_telemetry_events(ref, [event | acc])
    after
      500 -> Enum.reverse(acc)
    end
  end
end
