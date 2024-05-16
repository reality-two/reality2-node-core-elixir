defmodule Reality2Web.Router do
@moduledoc false

  use Reality2Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    # plug :put_root_layout, {Reality2Web.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", Reality2Web do
    pipe_through :browser
    get "/", Reality2Controller, :index
    get "/sentants", Reality2Controller, :index
  end

  pipeline :reality2 do
    plug :accepts, ["json"]
    # plug Reality2Web.HeadersAndAdminContext
  end

  scope "/reality2" do
    pipe_through :reality2

    forward "/", Absinthe.Plug,
    schema: Reality2Web.Schema,
    socket: Reality2Web.UserSocket,
    init_opts: [json_codec: Jason]
  end

  if Mix.env == :dev do
    forward "/graphiql", Absinthe.Plug.GraphiQL,
    schema: Reality2Web.Schema,
    socket: Reality2Web.UserSocket,
    # interface: :simple,
    interface: :advanced,
    # interface: :playground,
    context: %{pubsub: Reality2Web.Endpoint}
  end

  # Enable LiveDashboard in development
  # if Application.compile_env(:reality2_web, :dev_routes) do
  if Mix.env == :dev || Mix.env == :test do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: Reality2Web.Telemetry
    end
  end
end
