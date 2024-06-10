import Config

# Configure your database
config :reality2, Reality2.Repo,
  username: "postgres",
  password: "#6DDf9f9ce4",
  hostname: "localhost",
  database: "reality2_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :reality2_web, Reality2Web.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {0, 0, 0, 0}, port: 4002],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "2yz7/4pkTLPlQ54tltF1IOW37oNzSae4+8rmK4KF3LbZWzBfJfAi1y0RKxD5FI4b",
  watchers: [],

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
  https: [
    ip: {0, 0, 0, 0},
    port: 4001,
    cipher_suite: :strong,
    certfile: "priv/cert/selfsigned.pem",
    keyfile: "priv/cert/selfsigned_key.pem"
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "2yz7/4pkTLPlQ54tltF1IOW37oNzSae4+8rmK4KF3LbZWzBfJfAi1y0RKxD5FI4b",
  watchers: [],
  server: true
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Enable dev routes for dashboard and mailbox
config :reality2_web, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
