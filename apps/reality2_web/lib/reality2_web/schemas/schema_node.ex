defmodule Reality2Web.Schema.Node do
  @moduledoc false
  # Schema types and queries for node identity, peers, and hive information.

  use Absinthe.Schema.Notation

  alias Reality2Web.NodeResolver

  # --- Node identity ---

  object :node_info do
    field(:node_id, non_null(:string), description: "This node's UUID")
    field(:node_name, non_null(:string), description: "This node's human-readable name (e.g. R2Node_A3F7)")
    field(:hive_id, :string, description: "Hive UUID (nil if transnet not loaded)")
    field(:hive_name, :string, description: "Hive human-readable name")
    field(:hive_mode, :string, description: "Node's hive role: key_holder or member")
    field(:hive_compressed_id, :string, description: "4-byte compressed Hive ID (hex)")
  end

  # --- Peer reachability per transport ---

  object :transport_reachability do
    field(:last_seen, :string, description: "ISO8601 timestamp of last contact")
    field(:confidence, :integer, description: "Reachability confidence 0-255")
    field(:rssi, :integer, description: "Signal strength in dBm (BLE only)")
    field(:ip, :string, description: "IP address (WiFi only)")
  end

  object :peer_reachability do
    field(:ble, :transport_reachability)
    field(:wifi, :transport_reachability)
    field(:lora, :transport_reachability)
    field(:internet, :transport_reachability)
  end

  # --- Discovered peer ---

  object :peer do
    field(:node_id, non_null(:string), description: "Peer's node UUID")
    field(:node_name, :string, description: "Peer's human-readable name")
    field(:transport, :string, description: "Primary transport: ble_gatt, wifi_hotspot, lora")
    field(:rssi, :integer, description: "Signal strength in dBm")
    field(:connection_state, :string, description: "Discovery state")
    field(:hive_id, :string, description: "Peer's Hive UUID")
    field(:is_same_hive, :boolean, description: "Whether peer is in the same Hive")
    field(:hive_verified, :boolean, description: "Whether peer's Hive membership is verified")
    field(:sentant_count, :integer, description: "Number of sentants on this peer")
    field(:last_seen, :string, description: "ISO8601 timestamp of last contact")
    field(:reachability, :peer_reachability, description: "Per-transport reachability")
  end

  # --- Hive directory entry ---

  object :directory_sentant do
    field(:id, non_null(:string))
    field(:name, non_null(:string))
  end

  object :directory_node do
    field(:node_id, non_null(:string), description: "Node UUID")
    field(:name, :string, description: "Human-readable node name")
    field(:status, :string, description: "active, absent, or revoked")
    field(:hive_id, :string, description: "Hive this node belongs to")
    field(:sentants, list_of(:directory_sentant), description: "Sentants on this node")
    field(:reachability, :peer_reachability, description: "Per-transport reachability")
    field(:updated_at, :string, description: "Last update timestamp")
  end

  object :hive_directory do
    field(:hive_id, :string, description: "This Hive's UUID")
    field(:hive_name, :string, description: "This Hive's name")
    field(:my_node_id, :string, description: "This node's UUID in the directory")
    field(:directory_version, :integer, description: "Directory version counter")
    field(:nodes, list_of(:directory_node), description: "All known nodes")
  end

  # --- Queries ---

  object :node_queries do
    @desc "Get this node's identity and hive information"
    field :node_info, :node_info do
      resolve(&NodeResolver.node_info/3)
    end

    @desc "Get discovered peers from the mesh"
    field :peers, list_of(:peer) do
      resolve(&NodeResolver.peers/3)
    end

    @desc "Get the hive directory (all known nodes in the hive)"
    field :hive_directory, :hive_directory do
      resolve(&NodeResolver.hive_directory/3)
    end
  end
end
