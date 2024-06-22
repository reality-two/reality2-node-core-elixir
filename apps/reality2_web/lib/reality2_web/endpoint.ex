defmodule Reality2Web.Endpoint do
@moduledoc false
use Phoenix.Endpoint, otp_app: :reality2_web
use Absinthe.Phoenix.Endpoint


  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_reality2_web_key",
    signing_salt: "H0tk9UUi",
    same_site: "Lax",
  ]

  if Mix.env == :dev do
    socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
  end
  socket "/reality2", Reality2Web.UserSocket, websocket: true, longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: { :reality2_web, "priv/static/sites" },
    gzip: false
    # only: Reality2Web.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :reality2_web
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Reality2Web.Router
end
