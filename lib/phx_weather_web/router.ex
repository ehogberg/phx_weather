defmodule PhxWeatherWeb.Router do
  use PhxWeatherWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhxWeatherWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin_auth do
    plug :basic_auth
  end

  scope "/", PhxWeatherWeb do
    pipe_through :browser

    live "/", WeatherLive
  end

  scope "/", PhxWeatherWeb do
    pipe_through [:browser, :admin_auth]

    live "/admin", AdminLive
  end

  defp basic_auth(conn, _opts) do
    config = Application.get_env(:phx_weather, :basic_auth, username: "admin", password: "admin")
    Plug.BasicAuth.basic_auth(conn, config)
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:phx_weather, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PhxWeatherWeb.Telemetry
    end
  end
end
