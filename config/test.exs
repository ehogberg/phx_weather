import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :phx_weather, PhxWeatherWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "AIejkGBB558uMFW2psW5cetyFYH7r7U39cypOxg8lZn96M/oDe2coZDNMhDG2Ck2",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phx_weather, openweather_req_options: [
  plug: {Req.Test, PhxWeb.WeatherTest},
  retry: false
]

config :phx_weather, :openweather_api_key, ""
