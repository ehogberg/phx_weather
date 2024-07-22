defmodule PhxWeatherWeb.WeatherLive do
  use PhxWeatherWeb, :live_view

  alias PhxWeather
  alias PhxWeatherWeb.WeatherLive
  alias PhxWeatherWeb.WeatherLive.ShowLocation
  require Logger

  @impl true
  @spec mount(any(), any(), Phoenix.LiveView.Socket.t()) :: {:ok, map()}
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> init_location_stream()
      |> init_location_data()
      |> init_location_form()
    }
  end

  defp init_location_stream(socket) do
    socket
    |> stream_configure(:location_stream, dom_id: &"location-#{&1.component_id}")
    |> stream(:location_stream, [])
  end

  defp init_location_data(socket) do
    assign(socket, :location_data, %{})
  end

  defp init_location_form(socket) do
    assign(
      socket,
      :location_form,
      to_form(%{"location" => ""})
    )
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {valid_locations, invalid_locations} =
      params
      |> Map.get("locations", "Chicago|London|Paris")
      |> String.split("|")
      |> PhxWeather.geocode_location_list()

    {
      :noreply,
      socket
      |> warn_on_invalid_locations(invalid_locations)
      |> load_initial_locations(valid_locations)
    }
  end

  defp warn_on_invalid_locations(socket, invalid_locations)
       when invalid_locations == [],
       do: socket

  defp warn_on_invalid_locations(socket, invalid_locations) do
    _locations_warning_string = invalid_locations_message(invalid_locations)

    socket
    |> put_flash(:error, "Can't find a location:<br> Erehwon")
  end

  defp invalid_locations_message(_invalid_locations) do
    ""
  end

  defp load_initial_locations(socket, locations) do
    Enum.reduce(locations, socket, fn {:ok, l}, accum ->
      create_and_insert_geocode(accum, l)
    end)
  end

  @impl true
  def handle_event("add_location", %{"location" => location}, socket) do
    {
      :noreply,
      socket
      |> handle_add_location(location)
      |> init_location_form()
    }
  end

  @impl true
  def handle_event("remove_location", %{"location-id" => location_id}, socket) do
    location_id = String.to_integer(location_id)

    %{weather_data_id: weather_data_id} =
      Map.get(socket.assigns.location_data, location_id)

    PhxWeatherWeb.Endpoint.unsubscribe("weather_data:#{weather_data_id}")

    {
      :noreply,
      socket
      |> stream_delete(:location_stream, %{component_id: location_id})
      |> assign(:location_data, Map.delete(socket.assigns.location_data, location_id))
    }
  end

  @impl true
  def handle_info(
        {:weather_data_updated, %{id: weather_data_id, weather_data: weather_data}},
        socket
      ) do
    Logger.debug("Notified that weather data ID #{weather_data_id} has been updated.")

    {component_id, _} =
      Enum.find(
        socket.assigns.location_data,
        fn {_k, v} ->
          v.weather_data_id == weather_data_id
        end
      )

    send_update(ShowLocation, id: component_id, weather_data: weather_data)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:weather_data_id, {component_id, weather_data_id}}, socket) do
    Logger.debug("Received weather data ID #{weather_data_id} for component #{component_id}.")

    updated_location_data =
      Map.update!(
        socket.assigns.location_data,
        component_id,
        fn l ->
          Map.put(l, :weather_data_id, weather_data_id)
        end
      )

    Logger.debug(
      "Registering component #{component_id} for updates to weather data ID #{weather_data_id}"
    )

    PhxWeatherWeb.Endpoint.subscribe("weather_data:#{weather_data_id}")

    {
      :noreply,
      assign(socket, :location_data, updated_location_data)
    }
  end

  @impl true
  def handle_info(_evt, socket) do
    {:noreply, socket}
  end

  defp handle_add_location(socket, location) do
    case PhxWeather.geocode_location(location) do
      {:ok, %{lat: lat, lon: lon} = geo} ->
        if tracked_location?(socket.assigns.location_data, lat, lon) do
          put_flash(socket, :error, "#{location} weather is already being monitored.")
        else
          create_and_insert_geocode(socket, geo)
        end
      _ ->
        put_flash(socket, :error, "#{location} could not be found.")
    end
  end

  defp create_and_insert_geocode(socket, geo) do
    component_id = :rand.uniform(1_000_000_000)
    component = %{
      component_id: component_id,
      location: geo,
      weather_data_id: nil
    }

    socket
    |> stream_insert(:location_stream, component)
    |> assign(:location_data, Map.put(socket.assigns.location_data, component_id, component))
  end

  defp tracked_location?(location_data, lat, lon) do
    Enum.any?(
      location_data,
      fn {_, l} ->
        l.location.lat == lat && l.location.lon == lon
      end
    )
  end
end
