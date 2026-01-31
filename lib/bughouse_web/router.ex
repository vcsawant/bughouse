defmodule BughouseWeb.Router do
  use BughouseWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BughouseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BughouseWeb.UserAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BughouseWeb do
    pipe_through :browser

    get "/", PageController, :landing
    get "/game/new", PageController, :new_game
    post "/game", PageController, :create_game

    live_session :game,
      on_mount: [{BughouseWeb.UserAuth, :ensure_guest_player}],
      layout: {BughouseWeb.Layouts, :app} do
      live "/lobby/:invite_code", LobbyLive
      live "/game/:invite_code", GameLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", BughouseWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:bughouse, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BughouseWeb.Telemetry
    end
  end
end
