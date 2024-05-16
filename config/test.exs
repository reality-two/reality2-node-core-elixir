import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :reality2, Reality2.Repo,
  username: "postgres",
  password: "#6DDf9f9ce4",
  hostname: "localhost",
  database: "reality2_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :reality2_web, Reality2Web.Endpoint,
  # http: [ip: {127, 0, 0, 1}, port: 4002],
  # secret_key_base: "uDHCwdkWFOQffm6NJTBxtVeu159joiaJjTqnD6G45ODhwHdnlfdtTIb4juSFvZMk",
  # server: false

  # http: [ip: {0, 0, 0, 0}, port: 8080],
  # check_origin: false,
  # code_reloader: true,
  # debug_errors: true,
  # secret_key_base: "2yz7/4pkTLPlQ54tltF1IOW37oNzSae4+8rmK4KF3LbZWzBfJfAi1y0RKxD5FI4b",
  # watchers: []

  https: [
    ip: {0, 0, 0, 0},
    port: 4001,
    cipher_suite: :strong,
    keyfile: "priv/cert/selfsigned_key.pem",
    certfile: "priv/cert/selfsigned.pem"
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "2yz7/4pkTLPlQ54tltF1IOW37oNzSae4+8rmK4KF3LbZWzBfJfAi1y0RKxD5FI4b",
  watchers: []

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
