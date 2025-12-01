# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PhxWeather is a Phoenix LiveView application that displays real-time weather data for multiple locations using the OpenWeather API. The application uses Horde for distributed state management, allowing it to run as a clustered service with dynamic GenServer processes managing weather data per location.

## Common Commands

### Development
- `mix setup` - Install dependencies and setup assets (runs deps.get, assets.setup, assets.build)
- `mix phx.server` - Start Phoenix server (available at http://localhost:4000)
- `iex -S mix phx.server` - Start Phoenix server in IEx for debugging
- `mix phx.gen.cert` - Generate self-signed SSL certificates for HTTPS development (port 4001)

### Assets
- `mix assets.build` - Build assets (tailwind + esbuild)
- `mix assets.deploy` - Build and minify assets for production
- `mix tailwind phx_weather` - Compile Tailwind CSS
- `mix esbuild phx_weather` - Build JavaScript with esbuild

### Testing & Quality
- `mix test` - Run all tests
- `mix test test/path/to/test.exs` - Run a specific test file
- `mix test test/path/to/test.exs:42` - Run a specific test at line 42
- `mix format` - Format Elixir code using .formatter.exs configuration
- `mix credo` - Run static code analysis

### Production
- `mix phx.digest` - Digest and compress static files for production
- `PHX_SERVER=true mix release` - Create a production release

## Architecture

### Distributed Weather Data Management

The core architecture uses Horde (distributed process registry and supervisor) to manage weather data across a cluster:

1. **Horde.Registry** (`PhxWeather.WeatherRegistry`) - Distributed registry for weather data GenServers, keyed by `{lat, lon}` tuples
2. **Horde.DynamicSupervisor** (`PhxWeather.WeatherSupervisor`) - Distributed supervisor that spawns weather data processes on-demand
3. **WeatherData GenServer** (`lib/phx_weather/weather_data.ex`) - One GenServer per unique location, self-terminating after 2 minutes of client inactivity

### Weather Data Flow

1. User requests a location via `WeatherLive` LiveView
2. `PhxWeather.geocode_location/1` resolves location name to lat/lon via OpenWeather Geocoding API
3. `WeatherData.get_weather/2` is called with lat/lon:
   - Checks if a GenServer exists in the registry for this location
   - If not, spawns a new one via `Horde.DynamicSupervisor.start_child/2`
   - Returns weather data via GenServer call
4. GenServer fetches weather data from OpenWeather API every 60 seconds
5. Updates are broadcast via Phoenix.PubSub on topic `"weather_data:#{id}"`
6. LiveView components subscribe to updates and receive real-time weather changes
7. GenServer tracks `last_acknowledged_at` and shuts down after 2 minutes of no client activity

### LiveView Architecture

- **WeatherLive** (`lib/phx_weather_web/live/weather_live.ex`) - Main LiveView managing location streams
  - Uses `stream/3` for efficient rendering of multiple location components
  - Tracks location data in assigns with random component IDs
  - Subscribes to PubSub topics per weather_data_id for real-time updates
  - URL params support: `?locations=Chicago|London|Paris`

- **ShowLocation** Component (`lib/phx_weather_web/live/weather_live/show_location.ex`) - Stateful component per location
  - Receives updates via `send_update/3` when weather data changes
  - Sends acknowledgements back to WeatherData GenServer to prevent timeout

- **AdminLive** (`lib/phx_weather_web/live/admin_live.ex`) - Admin dashboard showing active weather stations
  - Uses JavaScript hooks to render a map visualization
  - Listens to `"weather_data_admin"` PubSub topic for new locations

### External Services

- **OpenWeatherService** (`lib/phx_weather/open_weather_service.ex`) - API client using `Req` library
  - Geocoding: `/geo/1.0/direct` endpoint
  - Weather data: `/data/2.5/weather` endpoint (imperial units)
  - Requires `OPENWEATHER_API_KEY` environment variable

### JavaScript Hooks

Located in `assets/js/hooks.js`, exports `PhxWeatherHooks` with:
- `Geolocation` - Browser geolocation integration
- `MapTrace` - Map visualization for admin dashboard

## Configuration

### Environment Variables

**Required for development and production:**
- `OPENWEATHER_API_KEY` - API key from https://home.openweathermap.org

**Production only:**
- `SECRET_KEY_BASE` - Generate with `mix phx.gen.secret`
- `PHX_HOST` - Hostname for the application
- `PORT` - HTTP port (default: 4000)
- `DNS_CLUSTER_QUERY` - For DNS-based clustering

### Clustering

- **Development**: Uses `Cluster.Strategy.LocalEpmd` for local clustering (configured in `config/dev.exs`)
- **Production**: Configured via `libcluster` topologies in `config/runtime.exs`

The application uses `libcluster` to automatically form clusters. In production, configure clustering via the `:libcluster` topologies setting.

## Deployment

### Kubernetes (GKE)

The application is configured for deployment to Google Kubernetes Engine:
- Deployment manifest: `k8s/deploy.yml` (3 replicas)
- GitHub Actions workflow: `.github/workflows/gke_build_deploy.yml`
- Secrets stored in Kubernetes: `phx-weather-config` (contains `openweather-service-api-key`, `phoenix-secret-key-base`, `phoenix-port`)
- Container port: 8080
- Resource limits: 512Mi memory, 500m CPU

Deployment happens automatically on push to `main` branch via GitHub Actions.

### Docker

Build with: `docker build -t phx-weather .`

The Dockerfile is configured for production releases.

## Key Patterns

### GenServer Lifecycle
Weather data GenServers are ephemeral - they spawn on-demand when a location is requested and shut down after 2 minutes of client inactivity. The timeout mechanism uses `last_acknowledged_at` tracking updated on each `:get_weather` call.

### PubSub Communication
- `"weather_data:#{id}"` - Per-location weather updates (subscribed by LiveViews)
- `"weather_data_admin"` - Admin notifications when locations are added (subscribed by AdminLive)

### State Management in LiveView
Uses Phoenix LiveView streams for efficient rendering of dynamic location lists. Location data is stored in assigns as a map keyed by component ID, with separate tracking of weather_data_id for PubSub subscriptions.

## Testing Notes

- Test environment uses `:test` env to skip OpenWeather API key requirement
- Test helper: `test/test_helper.exs` just calls `ExUnit.start()`
- ConnCase available for controller tests: `test/support/conn_case.ex`
