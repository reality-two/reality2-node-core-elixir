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
    field(:is_provisional, :boolean, description: "Whether this node's hive is still provisional")
    field(:version, :string, description: "Server software version")
    field(:build_id, :string, description: "Git commit short hash at build time")
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
    field(:address, :string, description: "Peer address (WiFi IP or BLE MAC)")
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

  # --- Mutation return types ---

  object :hive_info_result do
    field(:hive_id, :string, description: "Hive UUID")
    field(:hive_name, :string, description: "Hive human-readable name")
    field(:hive_mode, :string, description: "Node's hive role: key_holder or member")
    field(:is_provisional, :boolean, description: "Whether the hive is still provisional")
  end

  object :join_code_result do
    field(:code, non_null(:string), description: "4-character join code")
    field(:expires_in, non_null(:integer), description: "Seconds until code expires")
  end

  object :key_export_result do
    field(:encrypted_data, non_null(:string), description: "Base64-encoded encrypted key data")
  end

  object :join_request_result do
    field(:certificate, :json, description: "Signed node certificate")
    field(:hive_public_info, :json, description: "Hive public info (hive_id, name, public_key, created_at)")
  end

  object :pending_join_request do
    field(:id, non_null(:string), description: "Request ID")
    field(:node_name, non_null(:string), description: "Requesting node's name")
    field(:node_public_key, non_null(:string), description: "Requesting node's public key (base64)")
    field(:status, non_null(:string), description: "pending, approved, or denied")
    field(:submitted_at, non_null(:integer), description: "Unix timestamp")
  end

  object :join_status do
    field(:status, non_null(:string), description: "pending, approved, or denied")
    field(:certificate, :json, description: "Signed certificate (when approved)")
    field(:hive_public_info, :json, description: "Hive public info (when approved)")
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

    @desc "Get pending join requests (key holder only)"
    field :hive_pending_join_requests, list_of(:pending_join_request) do
      resolve(&NodeResolver.pending_join_requests/3)
    end

    @desc "Check the status of a join request (called by joiner)"
    field :hive_join_request_status, :join_status do
      arg(:request_id, non_null(:string))
      resolve(&NodeResolver.join_request_status/3)
    end
  end

  # --- Mutations ---

  object :node_mutations do
    @desc "Create (or reset) a hive with the given name"
    field :hive_create, :hive_info_result do
      arg(:name, non_null(:string))
      resolve(&NodeResolver.create_hive/3)
    end

    @desc "Mark the current provisional hive as established"
    field :hive_mark_established, :hive_info_result do
      resolve(&NodeResolver.mark_established/3)
    end

    @desc "Generate a 4-character join code for other nodes"
    field :hive_generate_join_code, :join_code_result do
      resolve(&NodeResolver.generate_join_code/3)
    end

    @desc "Export the hive key encrypted with a passphrase"
    field :hive_export_key, :key_export_result do
      arg(:passphrase, non_null(:string))
      resolve(&NodeResolver.export_key/3)
    end

    @desc "Import an encrypted hive key"
    field :hive_import_key, :hive_info_result do
      arg(:encrypted_data, non_null(:string))
      arg(:passphrase, non_null(:string))
      resolve(&NodeResolver.import_key/3)
    end
    @desc "Get this node's public key (base64-encoded)"
    field :hive_get_public_key, :string do
      resolve(&NodeResolver.get_public_key/3)
    end

    @desc "Process a join request (called on the key holder node)"
    field :hive_process_join_request, :join_request_result do
      arg(:code, non_null(:string))
      arg(:node_name, non_null(:string))
      arg(:node_public_key, non_null(:string))
      resolve(&NodeResolver.process_join_request/3)
    end

    @desc "Finalize joining a hive as a member (called on the joining node)"
    field :hive_join_as_member, :hive_info_result do
      arg(:hive_public_info, non_null(:json))
      arg(:certificate, non_null(:json))
      resolve(&NodeResolver.join_as_member/3)
    end

    @desc "Submit a join request (called on key holder by joiner's UI)"
    field :hive_submit_join_request, :pending_join_request do
      arg(:node_name, non_null(:string))
      arg(:node_public_key, non_null(:string))
      resolve(&NodeResolver.submit_join_request/3)
    end

    @desc "Approve a pending join request (key holder only)"
    field :hive_approve_join_request, :join_request_result do
      arg(:request_id, non_null(:string))
      resolve(&NodeResolver.approve_join_request/3)
    end

    @desc "Deny a pending join request (key holder only)"
    field :hive_deny_join_request, :boolean do
      arg(:request_id, non_null(:string))
      resolve(&NodeResolver.deny_join_request/3)
    end
  end
end
