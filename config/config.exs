# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :reality2, build_env: config_env()

# Configure Mix tasks and generators
config :reality2,
  ecto_repos: [Reality2.Repo]

config :reality2_web,
  ecto_repos: [Reality2.Repo],
  generators: [context_app: :reality2, binary_id: true]

# Configures the endpoint
config :reality2_web, Reality2Web.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [json: Reality2Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: Reality2.PubSub,
  live_view: [signing_salt: "/es9VuWV"],
  server: true

# config :blue_heron,
#   transport: [
#     device: "/dev/ttyS1",      # change to your HCI UART
#     speed: 115_200,
#     flow_control: :hardware    # or :none depending on hardware
#   ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Transient Networking configuration
config :reality2_transnet,
  # Bluetooth/GATT configuration
  r2_company_id: 0xFFFF,  # TODO: Replace with assigned company ID
  max_characteristic_size: 4096,
  # WiFi hotspot architecture (uses Reality2Web GraphQL on port 4005)
  # Site identifier for WiFi SSID generation
  # SSIDs are formatted as: R2-<SITE_ID>-<HOST_SHORT_ID>
  # Examples: R2-WAIROA-A3F7, R2-AUCKLAND-B2E9
  # Can be overridden by environment variable R2_SITE_ID
  # Default: "NODE"
  site_id: "NODE",

  # HIVE (Human Interactive Virtual Experience) configuration
  # A Hive is a collection of nodes acting as a single unified identity
  # The Hive ID is derived from the public key (self-certifying)
  hive_name: "DefaultHive",      # Human-readable name (can be changed)
  hive_data_dir: ".hive",        # Directory for identity persistence

  # Cloud nodes — hive members running on remote servers (backup, relay, analytics)
  # Each entry needs a WebSocket URL and the node's UUID
  # Example:
  #   cloud_nodes: [
  #     %{url: "wss://backup.example.com/mesh", node_id: "cloud-node-uuid"}
  #   ]
  cloud_nodes: []

# config/config.exs
config :mnesia,
  dir: ~c'.mnesia/#{config_env()}/#{node()}',
  storage: [disc_only_copies: [node()]]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
