defmodule AiReality2Transnet.TestNodeFactory do
  @moduledoc """
  Factory for building consistent test data: node entries, peer records,
  mesh messages, and hive identities.
  """

  @doc """
  Builds a node entry suitable for HiveDirectory.
  """
  def build_node_entry(overrides \\ %{}) do
    node_id = Map.get(overrides, :node_id, generate_uuid())

    Map.merge(%{
      name: Map.get(overrides, :name, "TestNode_#{random_hex(4)}"),
      compressed_id: :crypto.hash(:sha256, node_id) |> binary_part(0, 4),
      certificate: nil,
      status: :active,
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      sentants: [],
      hive_id: nil,
      reachability: default_reachability()
    }, Map.drop(overrides, [:node_id]))
  end

  @doc """
  Builds a peer record suitable for PeerManager.
  """
  def build_peer(overrides \\ %{}) do
    node_id = Map.get(overrides, :node_id, generate_uuid())
    now = System.system_time(:millisecond)

    Map.merge(%{
      node_id: node_id,
      node_name: "TestPeer_#{random_hex(4)}",
      transport: :ble_gatt,
      address: random_mac(),
      rssi: -60,
      hosting_priority: 50,
      sentants: [],
      capabilities: %{},
      discovered_at: now,
      last_seen: now,
      connection_state: :discovered,
      hive_id: nil,
      hive_public_key: nil,
      node_cert: nil,
      is_same_hive: false,
      hive_verified: false,
      reachability: %{
        ble: %{last_seen: DateTime.utc_now() |> DateTime.to_iso8601(), confidence: 200, rssi: -60},
        wifi: %{last_seen: nil, confidence: 0, ip: nil},
        lora: %{last_seen: nil, confidence: 0, via: nil},
        internet: %{last_seen: nil, confidence: 0}
      }
    }, overrides)
  end

  @doc """
  Builds a mesh message.
  """
  def build_mesh_message(overrides \\ %{}) do
    Map.merge(%{
      msg_id: :rand.uniform(0xFFFF),
      ttl: 5,
      type: :event,
      src_node_id: generate_uuid(),
      payload: <<>>
    }, overrides)
  end

  @doc """
  Builds a sentant entry for directory listings.
  """
  def build_sentant(overrides \\ %{}) do
    Map.merge(%{
      id: generate_uuid(),
      name: "TestSentant_#{random_hex(4)}",
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }, overrides)
  end

  @doc """
  Builds a minimal directory state for HiveDirectory tests.
  """
  def build_directory(overrides \\ %{}) do
    my_node_id = Map.get(overrides, :my_node_id, generate_uuid())
    hive_id = Map.get(overrides, :hive_id, generate_uuid())

    Map.merge(%{
      hive_id: hive_id,
      hive_name: "TestHive",
      my_node_id: my_node_id,
      directory_version: 1,
      nodes: %{
        my_node_id => build_node_entry(%{
          node_id: my_node_id,
          name: "Self",
          hive_id: hive_id
        })
      },
      trusted_hives: %{},
      foreign_nodes: %{}
    }, overrides)
  end

  @doc """
  Builds a cloud node config entry.
  """
  def build_cloud_config(overrides \\ %{}) do
    Map.merge(%{
      url: "wss://cloud-test.example.com/mesh",
      node_id: generate_uuid()
    }, overrides)
  end

  @doc """
  Generates a presence info map for LoRa presence encoding.
  """
  def build_presence_info(overrides \\ %{}) do
    Map.merge(%{
      hive_compressed: <<0xA3, 0xF7, 0xB2, 0xC1>>,
      capabilities: %{has_wifi: true, has_ble: true, is_relay: false, is_bridge: false,
                      is_anchor: false, is_sensor: false, is_mobile: false, is_cloud: false},
      sentant_count: 5,
      hosting_priority: 50,
      node_name_hash: 0x1234,
      cell_hint: 0x0001,
      dir_version: 42,
      energy_state: 200,
      backlog_count: 0
    }, overrides)
  end

  @doc """
  Generates a reachability map with defaults.
  """
  def default_reachability do
    %{
      ble: %{last_seen: nil, confidence: 0, rssi: nil},
      wifi: %{last_seen: nil, confidence: 0, ip: nil},
      lora: %{last_seen: nil, confidence: 0, via: nil},
      internet: %{last_seen: nil, confidence: 0}
    }
  end

  @doc """
  Generates a UUID v4 string.
  """
  def generate_uuid do
    hex = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    <<a::binary-8, b::binary-4, _::binary-1, c::binary-3, _::binary-1, d::binary-3, e::binary-12>> = hex
    "#{a}-#{b}-4#{c}-8#{d}-#{e}"
  end

  defp random_hex(bytes) do
    :crypto.strong_rand_bytes(bytes) |> Base.encode16(case: :lower)
  end

  defp random_mac do
    bytes = :crypto.strong_rand_bytes(6)
    bytes
    |> :binary.bin_to_list()
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> Enum.join(":")
  end
end
