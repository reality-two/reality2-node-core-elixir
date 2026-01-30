defmodule Reality2.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      %{id: :Bootstrap, start: {Reality2.Bootstrap, :start_link, [Reality2.Bootstrap]}},
      # Shared PubSub for all Reality2 apps (web, transnet, etc.)
      {Phoenix.PubSub, name: Reality2.PubSub},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: Reality2.Sentants},
      %{
        id: Reality2.Helpers.R2Process,
        start: {Reality2.Helpers.R2Process, :start_link, [Reality2.Helpers.R2Process]}
      },
      %{id: :SentantNames, start: {Reality2.Metadata, :start_link, [:SentantNames]}},
      %{id: :SentantIDs, start: {Reality2.Metadata, :start_link, [:SentantIDs]}},
      %{id: :Sentants, start: {Reality2.Metadata, :start_link, [:Sentants]}},
      %{id: :PNS_Routes, start: {Reality2.Metadata, :start_link, [:PNS_Routes]}},
      %{id: :PNS_NodeNames, start: {Reality2.Metadata, :start_link, [:PNS_NodeNames]}},
      %{id: :PNS_Peers, start: {Reality2.Metadata, :start_link, [:PNS_Peers]}},
      {Finch, name: Reality2.HTTPClient},
      # HTTP client for transient network peers with relaxed SSL (accepts self-signed certs)
      # SECURITY TODO: Replace verify: :verify_none with Hive-based certificate pinning.
      # Plan:
      # 1. When a node joins a Hive, the Hive CA cert is stored locally.
      # 2. Each node's self-signed cert is signed by the Hive CA during join.
      # 3. Configure this pool with verify: :verify_peer and cacertfile pointing
      #    to the Hive CA cert, so only nodes in the same Hive are trusted.
      # 4. Until then, verify: :verify_none is required because nodes use
      #    self-signed certs with no shared CA.
      {Finch,
        name: Reality2.TransnetHTTPClient,
        pools: %{
          :default => [
            conn_opts: [
              transport_opts: [verify: :verify_none]
            ]
          ]
        }
      },
      %{id: :Autostart, start: {Reality2.Autostart, :start_link, [Reality2.Autostart]}}
    ]

    Logger.info("[ai.reality2] started successfully")
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
