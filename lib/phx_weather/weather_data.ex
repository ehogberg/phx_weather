defmodule PhxWeather.WeatherData do
  @moduledoc false
  defstruct [
    :id, :name, :state, :country, :curr_temp, :feels_like,
    :projected_high, :projected_low, :humidity, :barometric_pressure,
    :current_conditions, :current_conditions_icon,
    :updated_at
  ]
end
