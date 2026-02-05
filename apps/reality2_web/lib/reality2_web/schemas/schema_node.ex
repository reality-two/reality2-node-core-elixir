defmodule Reality2Web.Schema.Node do
  @moduledoc false
  # Schema types and queries for node identity, peers, and trust group information.

  use Absinthe.Schema.Notation

  alias Reality2Web.NodeResolver

  # --- Node identity ---

  object :node_info do
    field(:node_id, non_null(:string), description: "This node's UUID")
    field(:node_name, non_null(:string), description: "This node's human-readable name (e.g. R2Node_A3F7)")
    field(:trust_group_id, :string, description: "Trust Group UUID (nil if transnet not loaded)")
    field(:trust_group_name, :string, description: "Trust Group human-readable name")
    field(:trust_group_mode, :string, description: "Node's trust group role: key_holder or member")
    field(:trust_group_compressed_id, :string, description: "4-byte compressed Trust Group ID (hex)")
    field(:is_provisional, :boolean, description: "Whether this node's trust group is still provisional")
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
    field(:trust_group_id, :string, description: "Peer's Trust Group UUID")
    field(:is_same_trust_group, :boolean, description: "Whether peer is in the same Trust Group")
    field(:trust_group_verified, :boolean, description: "Whether peer's Trust Group membership is verified")
    field(:sentant_count, :integer, description: "Number of sentants on this peer")
    field(:last_seen, :string, description: "ISO8601 timestamp of last contact")
    field(:reachability, :peer_reachability, description: "Per-transport reachability")
  end

  # --- Trust Group directory entry ---

  object :directory_sentant do
    field(:id, non_null(:string))
    field(:name, non_null(:string))
  end

  object :directory_node do
    field(:node_id, non_null(:string), description: "Node UUID")
    field(:name, :string, description: "Human-readable node name")
    field(:status, :string, description: "active, absent, or revoked")
    field(:trust_group_id, :string, description: "Trust Group this node belongs to")
    field(:sentants, list_of(:directory_sentant), description: "Sentants on this node")
    field(:reachability, :peer_reachability, description: "Per-transport reachability")
    field(:updated_at, :string, description: "Last update timestamp")
  end

  object :trust_group_directory do
    field(:trust_group_id, :string, description: "This Trust Group's UUID")
    field(:trust_group_name, :string, description: "This Trust Group's name")
    field(:my_node_id, :string, description: "This node's UUID in the directory")
    field(:directory_version, :integer, description: "Directory version counter")
    field(:nodes, list_of(:directory_node), description: "All known nodes")
  end

  # --- Mutation return types ---

  object :trust_group_info_result do
    field(:trust_group_id, :string, description: "Trust Group UUID")
    field(:trust_group_name, :string, description: "Trust Group human-readable name")
    field(:trust_group_mode, :string, description: "Node's trust group role: key_holder or member")
    field(:is_provisional, :boolean, description: "Whether the trust group is still provisional")
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
    field(:trust_group_public_info, :json, description: "Trust Group public info (trust_group_id, name, public_key, created_at)")
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
    field(:trust_group_public_info, :json, description: "Trust Group public info (when approved)")
  end

  object :ble_join_result do
    field(:status, non_null(:string), description: "pending, approved, denied, or error")
    field(:trust_group_id, :string, description: "Trust Group UUID (when approved)")
    field(:message, :string, description: "Human-readable status message")
  end

  object :trust_group_member do
    field(:node_id, non_null(:string), description: "Member's unique ID")
    field(:node_name, non_null(:string), description: "Member's human-readable name")
    field(:node_public_key, non_null(:string), description: "Member's Ed25519 public key (base64)")
    field(:member_type, non_null(:string), description: "node or viewer")
    field(:approved_at, non_null(:string), description: "ISO8601 timestamp when approved")
  end

  # --- Key Holders ---

  object :key_holder do
    field(:node_id, non_null(:string), description: "Key holder's node UUID")
    field(:node_name, :string, description: "Key holder's human-readable name")
    field(:device_name, :string, description: "Key holder's device description")
    field(:registered_at, non_null(:string), description: "ISO8601 timestamp when registered")
    field(:last_seen, :string, description: "ISO8601 timestamp of last activity")
    field(:is_local, non_null(:boolean), description: "Whether this is the local node")
  end

  # --- Inter-Group Trust ---

  object :trusted_group do
    field(:trust_group_id, non_null(:string), description: "Trusted group's UUID")
    field(:name, :string, description: "Trusted group's name")
    field(:public_key, :string, description: "Trusted group's public key (base64)")
    field(:permissions, list_of(:string), description: "Permission levels")
    field(:established_at, :string, description: "ISO8601 timestamp when trust established")
    field(:expires_at, :integer, description: "Unix timestamp when trust expires (null = permanent)")
    field(:sentant_filter, list_of(:string), description: "Sentants shared with this group")
    field(:status, :string, description: "Trust status: active or revoked")
  end

  object :trust_token do
    field(:token, non_null(:string), description: "8-character trust code")
    field(:trust_group_id, non_null(:string), description: "Issuing group's UUID")
    field(:trust_group_name, :string, description: "Issuing group's name")
    field(:expires_at, non_null(:integer), description: "Unix timestamp when token expires")
    field(:expires_in, non_null(:integer), description: "Seconds until expiration")
  end

  # --- Subscription types ---

  object :join_request_notification do
    field(:request_id, non_null(:string), description: "Unique request ID")
    field(:node_id, :string, description: "Requesting node's UUID (if available)")
    field(:node_name, non_null(:string), description: "Requesting node's name")
    field(:node_public_key, non_null(:string), description: "Requesting node's public key (base64)")
    field(:submitted_at, non_null(:integer), description: "Unix timestamp when submitted")
    field(:source, non_null(:string), description: "Request source: ble or graphql")
  end

  object :proximity_notification do
    field(:node_id, non_null(:string), description: "Nearby device's UUID")
    field(:node_name, :string, description: "Nearby device's name")
    field(:rssi, non_null(:integer), description: "Signal strength in dBm")
    field(:proximity, non_null(:string), description: "Proximity level: very_close, close, medium")
    field(:timestamp, non_null(:integer), description: "Unix timestamp when detected")
  end

  object :backup_prompt_notification do
    field(:device_name, non_null(:string), description: "Name of the first approved device")
    field(:trust_group_name, non_null(:string), description: "Name of the group")
    field(:trust_group_id, :string, description: "Group UUID")
    field(:timestamp, non_null(:integer), description: "Unix timestamp")
  end

  # --- Queries ---

  object :node_queries do
    @desc "Get this node's identity and trust group information"
    field :node_info, :node_info do
      resolve(&NodeResolver.node_info/3)
    end

    @desc "Get discovered peers from the mesh"
    field :peers, list_of(:peer) do
      resolve(&NodeResolver.peers/3)
    end

    @desc "Get the trust group directory (all known nodes in the trust group)"
    field :trust_group_directory, :trust_group_directory do
      resolve(&NodeResolver.trust_group_directory/3)
    end

    @desc "Get pending join requests (key holder only)"
    field :trust_group_pending_join_requests, list_of(:pending_join_request) do
      resolve(&NodeResolver.pending_join_requests/3)
    end

    @desc "Check the status of a join request (called by joiner)"
    field :trust_group_join_request_status, :join_status do
      arg(:request_id, non_null(:string))
      resolve(&NodeResolver.join_request_status/3)
    end

    @desc "Check the status of a BLE-based trust group join request"
    field :trust_group_ble_join_request_status, :ble_join_result do
      arg(:peer_id, non_null(:id))
      resolve(&NodeResolver.ble_join_request_status/3)
    end

    @desc "Get all approved trust group members (nodes and viewers)"
    field :trust_group_members, list_of(:trust_group_member) do
      arg(:member_type, :string, description: "Filter by type: node or viewer")
      resolve(&NodeResolver.trust_group_members/3)
    end

    @desc "List known trust group key holders"
    field :key_holders, list_of(:key_holder) do
      resolve(&NodeResolver.list_key_holders/3)
    end

    @desc "List trusted groups (inter-group federation)"
    field :trusted_groups, list_of(:trusted_group) do
      resolve(&NodeResolver.list_trusted_groups/3)
    end
  end

  # --- Mutations ---

  object :node_mutations do
    @desc "Create (or reset) a trust group with the given name"
    field :trust_group_create, :trust_group_info_result do
      arg(:name, non_null(:string))
      resolve(&NodeResolver.create_trust_group/3)
    end

    @desc "Mark the current provisional trust group as established"
    field :trust_group_mark_established, :trust_group_info_result do
      resolve(&NodeResolver.mark_established/3)
    end

    @desc "Generate a 4-character join code for other nodes"
    field :trust_group_generate_join_code, :join_code_result do
      resolve(&NodeResolver.generate_join_code/3)
    end

    @desc "Export the trust group key encrypted with a passphrase"
    field :trust_group_export_key, :key_export_result do
      arg(:passphrase, non_null(:string))
      resolve(&NodeResolver.export_key/3)
    end

    @desc "Import an encrypted trust group key"
    field :trust_group_import_key, :trust_group_info_result do
      arg(:encrypted_data, non_null(:string))
      arg(:passphrase, non_null(:string))
      resolve(&NodeResolver.import_key/3)
    end
    @desc "Get this node's public key (base64-encoded)"
    field :trust_group_get_public_key, :string do
      resolve(&NodeResolver.get_public_key/3)
    end

    @desc "Process a join request (called on the key holder node)"
    field :trust_group_process_join_request, :join_request_result do
      arg(:code, non_null(:string))
      arg(:node_name, non_null(:string))
      arg(:node_public_key, non_null(:string))
      resolve(&NodeResolver.process_join_request/3)
    end

    @desc "Finalize joining a trust group as a member (called on the joining node)"
    field :trust_group_join_as_member, :trust_group_info_result do
      arg(:trust_group_public_info, non_null(:json))
      arg(:certificate, non_null(:json))
      resolve(&NodeResolver.join_as_member/3)
    end

    @desc "Submit a join request (called on key holder by joiner's UI)"
    field :trust_group_submit_join_request, :pending_join_request do
      arg(:node_name, non_null(:string))
      arg(:node_public_key, non_null(:string))
      resolve(&NodeResolver.submit_join_request/3)
    end

    @desc "Approve a pending join request (key holder only)"
    field :trust_group_approve_join_request, :join_request_result do
      arg(:request_id, non_null(:string))
      resolve(&NodeResolver.approve_join_request/3)
    end

    @desc "Deny a pending join request (key holder only)"
    field :trust_group_deny_join_request, :boolean do
      arg(:request_id, non_null(:string))
      resolve(&NodeResolver.deny_join_request/3)
    end

    @desc "Submit a trust group join request via BLE GATT (called on the joiner node)"
    field :trust_group_ble_submit_join_request, :ble_join_result do
      arg(:peer_id, non_null(:id))
      arg(:node_name, non_null(:string))
      resolve(&NodeResolver.ble_submit_join_request/3)
    end

    @desc "Clear stale entries from the trust group directory (entries not updated in over 1 hour)"
    field :trust_group_directory_clear_stale, :integer do
      resolve(&NodeResolver.clear_stale_directory/3)
    end

    @desc "Remove a member from the trust group (key holder only)"
    field :trust_group_remove_member, :boolean do
      arg(:node_id, non_null(:string))
      resolve(&NodeResolver.remove_trust_group_member/3)
    end

    @desc "Generate a trust token to share with another trust group"
    field :trust_generate_token, :trust_token do
      arg(:permissions, list_of(:string), description: "Permission levels (default: read_only)")
      resolve(&NodeResolver.generate_trust_token/3)
    end

    @desc "Establish trust with another trust group (key holder only)"
    field :trust_establish, :trusted_group do
      arg(:trust_group_id, non_null(:string))
      arg(:trust_group_public_key, non_null(:string))
      arg(:trust_group_name, :string)
      arg(:permissions, list_of(:string))
      resolve(&NodeResolver.establish_trust/3)
    end

    @desc "Revoke trust with another trust group"
    field :trust_revoke, :boolean do
      arg(:trust_group_id, non_null(:string))
      resolve(&NodeResolver.revoke_trust/3)
    end
  end

  # --- Subscriptions ---

  object :node_subscriptions do
    @desc "Subscribe to new trust group join requests (key holder only)"
    field :join_request_received, :join_request_notification do
      config(fn _args, _ctx ->
        {:ok, topic: "trust_group:join_requests"}
      end)
    end

    @desc "Subscribe to proximity alerts when devices come very close (key holder only)"
    field :proximity_device_detected, :proximity_notification do
      config(fn _args, _ctx ->
        {:ok, topic: "trust_group:proximity"}
      end)
    end

    @desc "Subscribe to backup prompts when first device is approved (key holder only)"
    field :backup_prompt_received, :backup_prompt_notification do
      config(fn _args, _ctx ->
        {:ok, topic: "trust_group:backup_prompt"}
      end)
    end
  end
end
