# PhxWeather - Future Improvements

This document tracks planned improvements for the PhxWeather application. High priority items have been completed (see git history). This file contains medium and lower priority enhancements for future implementation.

---

## Completed (Reference)

- ✅ Error handling & resilience in WeatherData GenServer
- ✅ Retry logic with exponential backoff
- ✅ Telemetry events for observability
- ✅ Configuration hardcoded values fixed
- ✅ Dead code and bugs fixed in weather_live.ex
- ✅ Comprehensive test coverage added
- ✅ Logger deprecation warnings fixed
- ✅ Dependency updates (horde 0.10.0, libring 1.7.0, credo 1.7.13)

---

## MEDIUM PRIORITY - Code Quality & Maintainability

### 1. Documentation

**Status:** Not started
**Effort:** 2-3 days
**Impact:** High - Improves developer onboarding and maintainability

**Tasks:**
- [ ] Add `@doc` annotations for all public functions in `PhxWeather` context
- [ ] Add `@moduledoc` with examples for key modules (currently most are `@moduledoc false`)
- [ ] Add `@spec` type specifications for all public functions
- [ ] Document GenServer callbacks in `WeatherData`
- [ ] Document LiveView callbacks in `WeatherLive` and `AdminLive`
- [ ] Create architecture decision records (ADRs) for:
  - Why Horde was chosen for distributed state
  - 2-minute timeout decision rationale
  - PubSub architecture vs alternatives
  - Weather data polling frequency choice

**Current State:**
- Only 3 `@moduledoc` annotations exist, all set to `false`
- Only 1 `@spec` exists in the entire codebase (`weather_live.ex:10`)

**Example needed documentation:**

```elixir
@doc """
Retrieves weather data for a given location name.

This function geocodes the location name to coordinates, then spawns or
reuses a WeatherData GenServer to fetch the current weather.

## Examples

    iex> PhxWeather.retrieve_weather("Chicago")
    {:ok, %WeatherData{name: "Chicago", curr_temp: 75, ...}}

    iex> PhxWeather.retrieve_weather("InvalidCity12345")
    {:error, :unknown_location, "InvalidCity12345"}
"""
@spec retrieve_weather(String.t()) :: {:ok, WeatherData.t()} | {:error, atom(), any()}
def retrieve_weather(name) when is_binary(name) do
  # ...
end
```

### 2. Type Specifications

**Status:** Not started
**Effort:** 1-2 days
**Impact:** Medium - Improves code quality and catches bugs

**Tasks:**
- [ ] Add `@spec` for all public functions in `lib/phx_weather.ex`
- [ ] Add `@spec` for GenServer callbacks in `lib/phx_weather/weather_data.ex`
- [ ] Add `@spec` for LiveView callbacks
- [ ] Add `@type` definitions for complex data structures
- [ ] Consider using Dialyzer for static type checking

**Files needing specs:**
- `lib/phx_weather.ex` - All public functions
- `lib/phx_weather/weather_data.ex` - GenServer callbacks
- `lib/phx_weather/open_weather_service.ex` - API functions
- `lib/phx_weather_web/live/weather_live.ex` - Event handlers

### 3. Code Organization

**Status:** Not started
**Effort:** 1-2 days
**Impact:** Medium - Better separation of concerns

**Current Issues:**
- Business logic scattered in LiveView (`weather_live.ex:170-203`)
- `PhxWeather` context is thin wrapper, just delegates
- Location tracking logic could be its own context

**Proposed Changes:**

**Option A: Extract Locations Context**
```elixir
# lib/phx_weather/locations.ex
defmodule PhxWeather.Locations do
  @moduledoc """
  Context for managing tracked weather locations.
  """

  @spec track_location?(map(), float(), float()) :: boolean()
  def tracked_location?(location_data, lat, lon)

  @spec generate_component_id() :: integer()
  def generate_component_id()

  @spec validate_location(String.t()) :: {:ok, map()} | {:error, atom()}
  def validate_location(name)
end
```

**Option B: Enrich PhxWeather Context**
- Move geocoding logic from `OpenWeatherService` to `PhxWeather`
- Add domain-specific functions vs. pure delegation
- Better error handling and validation at context boundary

**Tasks:**
- [ ] Decide on context boundaries
- [ ] Extract business logic from LiveView
- [ ] Move location validation to context layer
- [ ] Add integration tests for new context functions

---

## LOWER PRIORITY - Performance & Features

### 4. Performance Optimizations

**Status:** Not started
**Effort:** 3-5 days
**Impact:** Medium - Reduces API costs and improves responsiveness

#### 4.1 Caching Layer

**Problem:** No caching means every client request hits the API

**Proposed Solution:**
```elixir
# lib/phx_weather/weather_cache.ex
defmodule PhxWeather.WeatherCache do
  use GenServer

  # ETS-based cache with TTL
  # Cache weather data for 5 minutes
  # De-duplicate simultaneous requests for same location
end
```

**Tasks:**
- [ ] Implement ETS-based cache with TTL
- [ ] Add cache hit/miss telemetry
- [ ] De-duplicate concurrent requests for same location
- [ ] Add cache invalidation strategy
- [ ] Measure cache hit rate and adjust TTL

**Expected Impact:**
- Reduce API calls by 80-90%
- Faster response times for cached data
- Lower OpenWeather API costs

#### 4.2 Rate Limiting

**Problem:** No protection against API quota exhaustion

**Tasks:**
- [ ] Implement client-side rate limiting for OpenWeather API
- [ ] Track API usage per time window
- [ ] Add backoff when approaching quota
- [ ] Log rate limit violations
- [ ] Add telemetry for rate limit metrics

**Implementation:**
```elixir
# lib/phx_weather/rate_limiter.ex
defmodule PhxWeather.RateLimiter do
  # Token bucket or sliding window algorithm
  # OpenWeather free tier: 60 calls/minute
end
```

#### 4.3 Adaptive Polling

**Problem:** Fixed 60-second polling regardless of data freshness

**Current:** Weather data fetched every 60 seconds
**Reality:** OpenWeather updates most locations every ~10 minutes

**Proposed:**
```elixir
defp calculate_next_poll_interval(last_update_time) do
  time_since_update = DateTime.diff(DateTime.utc_now(), last_update_time)

  cond do
    time_since_update < 300 -> 120_000  # 2 minutes if recently updated
    time_since_update < 600 -> 60_000   # 1 minute if moderately fresh
    true -> 30_000                       # 30 seconds if stale
  end
end
```

**Tasks:**
- [ ] Implement adaptive polling based on `data_updated_at`
- [ ] Add configuration for polling intervals
- [ ] Monitor polling frequency via telemetry
- [ ] A/B test optimal intervals

### 5. Observability

**Status:** Partially complete (telemetry events added)
**Effort:** 2-3 days
**Impact:** High - Critical for production monitoring

#### 5.1 Structured Logging

**Current State:**
```elixir
Logger.debug("Checking to see if any instance is still using weather data for id #{weather_data_id}")
```

**Proposed:**
```elixir
Logger.info("Weather data status check",
  weather_data_id: weather_data_id,
  lat: lat,
  lon: lon,
  last_acknowledged: last_acknowledged_at,
  time_remaining: timeout_remaining
)
```

**Tasks:**
- [ ] Convert all Logger calls to structured format
- [ ] Add consistent metadata (location, weather_data_id, etc.)
- [ ] Use appropriate log levels:
  - `debug`: Development/troubleshooting details
  - `info`: Normal lifecycle events
  - `warning`: Degraded performance (API failures)
  - `error`: Critical issues requiring attention
- [ ] Remove debug logs or guard behind config

#### 5.2 Telemetry Integration

**Status:** Events added, not consumed
**Tasks:**
- [ ] Create telemetry consumer module
- [ ] Integrate with Phoenix.Telemetry dashboard
- [ ] Add custom dashboard for weather metrics
- [ ] Set up alerting for critical metrics

**Key Metrics to Track:**
```elixir
# Already instrumented:
[:phx_weather, :weather_data, :initialized]
[:phx_weather, :weather_data, :init_failed]
[:phx_weather, :weather_data, :terminated]
[:phx_weather, :weather_data, :api_call]

# Proposed additions:
[:phx_weather, :cache, :hit]
[:phx_weather, :cache, :miss]
[:phx_weather, :rate_limiter, :rejected]
[:phx_weather, :locations, :added]
[:phx_weather, :locations, :removed]
```

**Dashboard Panels:**
- Active weather processes gauge
- API call rate and latency histogram
- Cache hit rate percentage
- Error rate by type
- Weather data age distribution

#### 5.3 Health Checks

**Tasks:**
- [ ] Add `/health` endpoint for k8s probes
- [ ] Check OpenWeather API connectivity
- [ ] Monitor Horde cluster health
- [ ] Track oldest weather data age
- [ ] Alert on stale data (> 30 minutes)

### 6. Security

**Status:** Not started
**Effort:** 1-2 days
**Impact:** High for production

#### 6.1 Admin Dashboard Authentication

**Problem:** `/admin` route is publicly accessible

**Tasks:**
- [ ] Add authentication to admin routes
- [ ] Implement basic auth for production (minimum)
- [ ] Consider proper auth system if user accounts exist
- [ ] Add role-based access control if needed

**Quick Win - Basic Auth:**
```elixir
# lib/phx_weather_web/router.ex
pipeline :admin do
  plug :browser
  plug BasicAuth, use_config: {:phx_weather, :admin_auth}
end

scope "/admin" do
  pipe_through :admin
  live "/", AdminLive
end
```

```elixir
# config/runtime.exs (production only)
config :phx_weather, :admin_auth,
  username: System.fetch_env!("ADMIN_USERNAME"),
  password: System.fetch_env!("ADMIN_PASSWORD")
```

#### 6.2 Rate Limiting on User Actions

**Problem:** No throttling on location additions

**Risk:** User could spam OpenWeather API

**Tasks:**
- [ ] Add client-side rate limiting (LiveView)
- [ ] Track location additions per session/IP
- [ ] Limit to 10 locations per minute per client
- [ ] Add flash message when rate limited

### 7. User Experience Enhancements

**Status:** Not started
**Effort:** 2-4 days
**Impact:** Medium - Improves user satisfaction

#### 7.1 Loading States

**Current:** No indication when fetching data

**Tasks:**
- [ ] Add loading spinner during geocoding
- [ ] Show skeleton loading for weather cards
- [ ] Indicate when weather data is being refreshed
- [ ] Add loading state for initial location load

#### 7.2 Error Handling UX

**Current:** Flash messages, no retry

**Improvements:**
- [ ] Add retry button when weather fetch fails
- [ ] Show "last updated X minutes ago" on stale data
- [ ] Distinguish between network errors and API errors
- [ ] Provide helpful error messages (not just "could not be found")

#### 7.3 Optimistic UI Updates

**Tasks:**
- [ ] Show location card immediately when adding
- [ ] Update with real data when received
- [ ] Handle failures gracefully (remove on error)
- [ ] Smooth transitions and animations

#### 7.4 Better Duplicate Handling

**Current:** Flash message only

**Proposed:**
- [ ] Visual indicator on existing card when duplicate attempted
- [ ] Scroll to existing location
- [ ] Highlight for 2 seconds
- [ ] More informative message

---

## Alignment with TODO.md

Your existing TODO.md contains:

### Already Completed
- ✅ Smartly shut down unused weather station processes (2-minute timeout implemented)

### Still Pending
- [ ] Add localized timezone support
- [ ] Improve README: add project overview and developer setup
- [ ] ~~Containerize app and push container image to Docker~~ (Already done - Dockerfile exists)
- [ ] ~~Deploy to Google App Engine~~ (Already deployed to GKE)
- [ ] Add permalink generation support
- [ ] Flesh out admin screen functionality: list of weather data processes, select on globe, show recent weather

### New Recommendations from This Analysis
- [ ] Implement caching layer (reduce API costs)
- [ ] Add admin authentication
- [ ] Enhanced observability with metrics dashboard
- [ ] Improve error handling UX

---

## Implementation Priority Recommendation

If implementing incrementally, suggested order:

### Phase 1 (Next Sprint)
1. Documentation (`@doc`, `@spec`, `@moduledoc`)
2. Admin authentication (security critical)
3. Structured logging (ops visibility)

### Phase 2 (Following Sprint)
4. Caching layer (cost reduction)
5. Rate limiting (API protection)
6. Loading states & UX improvements

### Phase 3 (Future)
7. Metrics dashboard integration
8. Adaptive polling
9. Code reorganization
10. Health checks

---

## Notes

- All telemetry events are already instrumented but not consumed
- Test coverage is comprehensive for core functionality
- The system is production-ready as-is, these are enhancements
- Caching would provide the biggest immediate ROI
- Documentation would provide the biggest long-term ROI

---

## Testing Strategy for Future Changes

When implementing these improvements:

1. **Caching:** Test cache hit rates, TTL behavior, concurrent access
2. **Rate Limiting:** Test quota enforcement, backoff behavior
3. **Admin Auth:** Test unauthorized access, credential validation
4. **UX Changes:** Manual testing, visual regression tests
5. **Observability:** Verify metrics are collected, dashboards render

---

**Last Updated:** 2025-11-30
**Status:** Medium and Lower priority items pending implementation
**High Priority Items:** All completed ✅
