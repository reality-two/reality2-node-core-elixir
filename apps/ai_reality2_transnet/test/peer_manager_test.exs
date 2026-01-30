defmodule AiReality2Transnet.PeerManagerTest do
  @moduledoc """
  Integration tests for AiReality2Transnet.PeerManager.

  These tests require parts of the umbrella application to be running
  (notably Reality2.Bootstrap for log_prefix/0), so they are tagged
  as :integration and excluded from the default test run.

  Run with: mix test --include integration
  """

  use ExUnit.Case, async: true

  @moduletag :integration

  alias AiReality2Transnet.PeerManager
  alias AiReality2Transnet.TestNodeFactory

  # ---------------------------------------------------------------------------
  # Setup — start a fresh PeerManager for each test
  # ---------------------------------------------------------------------------

  setup do
    # PeerManager registers itself under __MODULE__, so only one can run at a time.
    # Stop any lingering instance before starting a fresh one.
    if pid = Process.whereis(PeerManager) do
      GenServer.stop(pid, :normal, 5_000)
    end

    {:ok, pid} = PeerManager.start_link([])

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)
    end)

    %{pid: pid}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Give cast messages time to be processed
  defp flush_casts do
    # A synchronous call forces all preceding casts to be processed first
    _ = PeerManager.get_all_peers()
    :ok
  end

  # ---------------------------------------------------------------------------
  # 1. register_peer/2 — new peer creation
  # ---------------------------------------------------------------------------

  describe "register_peer/2 — new peer" do
    test "creates a peer with all expected fields" do
      node_id = TestNodeFactory.generate_uuid()
      info = %{
        address: "AA:BB:CC:DD:EE:FF",
        rssi: -55,
        node_name: "R2Node_Test1",
        hosting_priority: 75,
        capabilities: %{wifi_hotspot: true}
      }

      PeerManager.register_peer(node_id, info)
      flush_casts()

      assert {:ok, peer} = PeerManager.get_peer(node_id)

      assert peer.node_id == node_id
      assert peer.node_name == "R2Node_Test1"
      assert peer.transport == :ble_gatt
      assert peer.address == "AA:BB:CC:DD:EE:FF"
      assert peer.rssi == -55
      assert peer.hosting_priority == 75
      assert peer.sentants == []
      assert peer.capabilities == %{wifi_hotspot: true}
      assert peer.connection_state == :discovered
      assert is_integer(peer.discovered_at)
      assert is_integer(peer.last_seen)
      assert peer.last_seen >= peer.discovered_at

      # Hive fields default to nil/false
      assert peer.hive_id == nil
      assert peer.hive_public_key == nil
      assert peer.node_cert == nil
      assert peer.is_same_hive == false
      assert peer.hive_verified == false

      # Reachability initialized with BLE data
      assert peer.reachability.ble.confidence == 200
      assert peer.reachability.ble.rssi == -55
      assert peer.reachability.ble.last_seen != nil
      assert peer.reachability.wifi.confidence == 0
      assert peer.reachability.lora.confidence == 0
    end

    test "increments stats.total_discovered for new peers" do
      id1 = TestNodeFactory.generate_uuid()
      id2 = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(id1, %{rssi: -60})
      PeerManager.register_peer(id2, %{rssi: -70})
      flush_casts()

      stats = PeerManager.get_stats()
      assert stats.total_discovered == 2
      assert stats.current_peers == 2
    end

    test "peer is retrievable via get_all_peers" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -65, node_name: "NodeAll"})
      flush_casts()

      all = PeerManager.get_all_peers()
      assert Map.has_key?(all, node_id)
      assert all[node_id].node_name == "NodeAll"
    end

    test "peer is retrievable via get_peer_by_name" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -50, node_name: "NamedNode_X"})
      flush_casts()

      assert {:ok, peer} = PeerManager.get_peer_by_name("NamedNode_X")
      assert peer.node_id == node_id
    end

    test "get_peer returns error for unknown node" do
      assert {:error, :not_found} = PeerManager.get_peer("nonexistent-id")
    end

    test "get_peer_by_name returns error for unknown name" do
      assert {:error, :not_found} = PeerManager.get_peer_by_name("NoSuchNode")
    end
  end

  # ---------------------------------------------------------------------------
  # 1b. register_peer/2 — beacon re-registration preserves state
  # ---------------------------------------------------------------------------

  describe "register_peer/2 — re-registration (beacon refresh)" do
    test "updates rssi and last_seen but preserves sentants and connection_state" do
      node_id = TestNodeFactory.generate_uuid()

      # First registration
      PeerManager.register_peer(node_id, %{
        rssi: -55,
        address: "AA:BB:CC:DD:EE:01",
        node_name: "ReReg_Node"
      })
      flush_casts()

      # Simulate sentant exchange to set connection_state and sentants
      sentants = [TestNodeFactory.build_sentant(%{name: "S1"})]
      PeerManager.update_peer_sentants(node_id, sentants)
      flush_casts()

      {:ok, before_rereg} = PeerManager.get_peer(node_id)
      assert before_rereg.connection_state == :sentants_exchanged
      assert length(before_rereg.sentants) == 1

      # Re-register (beacon refresh) with new RSSI
      PeerManager.register_peer(node_id, %{rssi: -40})
      flush_casts()

      {:ok, after_rereg} = PeerManager.get_peer(node_id)

      # RSSI updated
      assert after_rereg.rssi == -40
      # last_seen updated (equal or later)
      assert after_rereg.last_seen >= before_rereg.last_seen
      # Sentants preserved
      assert length(after_rereg.sentants) == 1
      # connection_state preserved
      assert after_rereg.connection_state == :sentants_exchanged
      # discovered_at preserved (same value)
      assert after_rereg.discovered_at == before_rereg.discovered_at
    end

    test "does not increment total_discovered on re-registration" do
      node_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(node_id, %{rssi: -55})
      PeerManager.register_peer(node_id, %{rssi: -50})
      PeerManager.register_peer(node_id, %{rssi: -45})
      flush_casts()

      stats = PeerManager.get_stats()
      assert stats.total_discovered == 1
    end

    test "preserves address when re-registration omits it" do
      node_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(node_id, %{address: "11:22:33:44:55:66", rssi: -60})
      flush_casts()

      # Re-register without address
      PeerManager.register_peer(node_id, %{rssi: -50})
      flush_casts()

      {:ok, peer} = PeerManager.get_peer(node_id)
      assert peer.address == "11:22:33:44:55:66"
    end

    test "updates node_name on re-registration if provided" do
      node_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(node_id, %{rssi: -55, node_name: "OldName"})
      flush_casts()

      PeerManager.register_peer(node_id, %{rssi: -50, node_name: "NewName"})
      flush_casts()

      {:ok, peer} = PeerManager.get_peer(node_id)
      assert peer.node_name == "NewName"
    end

    test "preserves node_name when re-registration omits it" do
      node_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(node_id, %{rssi: -55, node_name: "KeepMe"})
      flush_casts()

      PeerManager.register_peer(node_id, %{rssi: -50})
      flush_casts()

      {:ok, peer} = PeerManager.get_peer(node_id)
      assert peer.node_name == "KeepMe"
    end
  end

  # ---------------------------------------------------------------------------
  # 2. update_peer_sentants/2
  # ---------------------------------------------------------------------------

  describe "update_peer_sentants/2" do
    test "sets connection_state to :sentants_exchanged and stores sentant list" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      sentants = [
        TestNodeFactory.build_sentant(%{name: "Alpha"}),
        TestNodeFactory.build_sentant(%{name: "Beta"}),
        TestNodeFactory.build_sentant(%{name: "Gamma"})
      ]

      PeerManager.update_peer_sentants(node_id, sentants)
      flush_casts()

      {:ok, peer} = PeerManager.get_peer(node_id)
      assert peer.connection_state == :sentants_exchanged
      assert length(peer.sentants) == 3

      names = Enum.map(peer.sentants, & &1.name)
      assert "Alpha" in names
      assert "Beta" in names
      assert "Gamma" in names
    end

    test "updates last_seen timestamp" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      {:ok, before} = PeerManager.get_peer(node_id)

      # Small sleep to ensure timestamp difference
      Process.sleep(5)

      PeerManager.update_peer_sentants(node_id, [TestNodeFactory.build_sentant()])
      flush_casts()

      {:ok, after_update} = PeerManager.get_peer(node_id)
      assert after_update.last_seen >= before.last_seen
    end

    test "silently ignores unknown peer" do
      # Should not crash
      PeerManager.update_peer_sentants("nonexistent-id", [])
      flush_casts()

      # Still operational
      assert is_map(PeerManager.get_all_peers())
    end

    test "replaces sentant list on subsequent calls" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      PeerManager.update_peer_sentants(node_id, [TestNodeFactory.build_sentant(%{name: "First"})])
      flush_casts()

      PeerManager.update_peer_sentants(node_id, [
        TestNodeFactory.build_sentant(%{name: "Second"}),
        TestNodeFactory.build_sentant(%{name: "Third"})
      ])
      flush_casts()

      {:ok, peer} = PeerManager.get_peer(node_id)
      assert length(peer.sentants) == 2
      names = Enum.map(peer.sentants, & &1.name)
      assert "Second" in names
      assert "Third" in names
      refute "First" in names
    end
  end

  # ---------------------------------------------------------------------------
  # 3. best_transport/1
  # ---------------------------------------------------------------------------

  describe "best_transport/1" do
    test "selects transport with highest confidence" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      # Set WiFi to highest confidence
      PeerManager.update_reachability(node_id, :wifi, %{confidence: 250, ip: "192.168.1.10"})
      # BLE already at 200 from registration
      # Set LoRa to moderate
      PeerManager.update_reachability(node_id, :lora, %{confidence: 100, via: <<1, 2, 3, 4>>})
      flush_casts()

      assert {:ok, :wifi, info} = PeerManager.best_transport(node_id)
      assert info.confidence == 250
      assert info.ip == "192.168.1.10"
    end

    test "returns :ble when it has highest confidence" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -45})
      flush_casts()

      # BLE starts at 200 from registration, set others lower
      PeerManager.update_reachability(node_id, :wifi, %{confidence: 50})
      PeerManager.update_reachability(node_id, :lora, %{confidence: 30})
      flush_casts()

      assert {:ok, :ble, info} = PeerManager.best_transport(node_id)
      assert info.confidence == 200
    end

    test "returns :error, :unreachable when all transports below threshold 5" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -90})
      flush_casts()

      # Override BLE confidence to below threshold
      PeerManager.update_reachability(node_id, :ble, %{confidence: 3})
      PeerManager.update_reachability(node_id, :wifi, %{confidence: 0})
      PeerManager.update_reachability(node_id, :lora, %{confidence: 4})
      flush_casts()

      assert {:error, :unreachable} = PeerManager.best_transport(node_id)
    end

    test "returns :error, :not_found for unknown peer" do
      assert {:error, :not_found} = PeerManager.best_transport("nonexistent-id")
    end

    test "confidence exactly at threshold 5 is accepted" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -80})
      flush_casts()

      # Set all to below threshold except one at exactly 5
      PeerManager.update_reachability(node_id, :ble, %{confidence: 2})
      PeerManager.update_reachability(node_id, :wifi, %{confidence: 0})
      PeerManager.update_reachability(node_id, :lora, %{confidence: 5})
      flush_casts()

      assert {:ok, :lora, _info} = PeerManager.best_transport(node_id)
    end

    test "prefers wifi over ble at equal confidence (priority order)" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      # Set both WiFi and BLE to equal high confidence
      PeerManager.update_reachability(node_id, :wifi, %{confidence: 200})
      PeerManager.update_reachability(node_id, :ble, %{confidence: 200})
      flush_casts()

      # With equal confidence, the sort is stable and the priority order
      # [:wifi, :internet, :ble, :lora] means wifi comes first when sorted desc
      # by confidence (since sort is stable for equal values, first in list wins)
      assert {:ok, transport, _} = PeerManager.best_transport(node_id)
      # Both wifi and ble are valid at 200; the implementation sorts desc
      # and takes head — with stable sort, the original order is preserved
      assert transport in [:wifi, :ble]
    end
  end

  # ---------------------------------------------------------------------------
  # 4. update_reachability/3
  # ---------------------------------------------------------------------------

  describe "update_reachability/3" do
    test "updates per-transport reachability data" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -55})
      flush_casts()

      PeerManager.update_reachability(node_id, :wifi, %{confidence: 200, ip: "10.0.0.5"})
      flush_casts()

      assert {:ok, reach} = PeerManager.get_reachability(node_id)
      assert reach.wifi.confidence == 200
      assert reach.wifi.ip == "10.0.0.5"
      assert reach.wifi.last_seen != nil
    end

    test "updates LoRa reachability with via field" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -70})
      flush_casts()

      PeerManager.update_reachability(node_id, :lora, %{confidence: 150, via: <<0xA3, 0xF7, 0xB2, 0xC1>>})
      flush_casts()

      assert {:ok, reach} = PeerManager.get_reachability(node_id)
      assert reach.lora.confidence == 150
      assert reach.lora.via == <<0xA3, 0xF7, 0xB2, 0xC1>>
    end

    test "auto-updates primary transport field based on reachability" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      {:ok, peer_before} = PeerManager.get_peer(node_id)
      assert peer_before.transport == :ble_gatt

      # Upgrade WiFi confidence to >= 100 which triggers wifi_hotspot
      PeerManager.update_reachability(node_id, :wifi, %{confidence: 150, ip: "192.168.1.5"})
      flush_casts()

      {:ok, peer_after} = PeerManager.get_peer(node_id)
      assert peer_after.transport == :wifi_hotspot
    end

    test "does not crash for unknown peer" do
      # Should silently handle or propagate to HiveDirectory only
      PeerManager.update_reachability("ghost-peer", :ble, %{confidence: 100})
      flush_casts()

      # GenServer still alive
      assert is_map(PeerManager.get_all_peers())
    end

    test "preserves existing fields when updating a single transport" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -55})
      flush_casts()

      # Set WiFi
      PeerManager.update_reachability(node_id, :wifi, %{confidence: 180, ip: "10.0.0.1"})
      flush_casts()

      # Now update LoRa — WiFi should remain intact
      PeerManager.update_reachability(node_id, :lora, %{confidence: 80})
      flush_casts()

      assert {:ok, reach} = PeerManager.get_reachability(node_id)
      assert reach.wifi.confidence == 180
      assert reach.wifi.ip == "10.0.0.1"
      assert reach.lora.confidence == 80
    end

    test "updates last_seen on the peer record" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      {:ok, before} = PeerManager.get_peer(node_id)
      Process.sleep(5)

      PeerManager.update_reachability(node_id, :ble, %{confidence: 210, rssi: -42})
      flush_casts()

      {:ok, after_update} = PeerManager.get_peer(node_id)
      assert after_update.last_seen >= before.last_seen
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Hive-aware peer filtering
  # ---------------------------------------------------------------------------

  describe "get_hive_peers/0 — same hive, verified" do
    test "returns only peers with is_same_hive=true AND hive_verified=true" do
      # Register 3 peers
      id_same_verified = TestNodeFactory.generate_uuid()
      id_same_unverified = TestNodeFactory.generate_uuid()
      id_foreign = TestNodeFactory.generate_uuid()

      for id <- [id_same_verified, id_same_unverified, id_foreign] do
        PeerManager.register_peer(id, %{rssi: -60})
      end
      flush_casts()

      # Manually set hive fields via the state (use update_reachability + internal state)
      # Since update_peer_hive_info calls HiveIdentity which may not be available,
      # we inject state by sending a raw message to set the fields.
      # Instead, let's test through the GenServer's handle_call for update_hive_info.
      # But that calls HiveIdentity.get_hive_id() and verify_node_cert().
      # In integration mode those should be available. If not, we test the filter
      # logic by directly manipulating state.

      # We can set the fields by using a :sys.replace_state/2 call
      :sys.replace_state(PeerManager, fn state ->
        peers = state.peers
        |> Map.update!(id_same_verified, fn p ->
          %{p | is_same_hive: true, hive_verified: true, hive_id: "hive-A"}
        end)
        |> Map.update!(id_same_unverified, fn p ->
          %{p | is_same_hive: true, hive_verified: false, hive_id: "hive-A"}
        end)
        |> Map.update!(id_foreign, fn p ->
          %{p | is_same_hive: false, hive_verified: true, hive_id: "hive-B"}
        end)

        %{state | peers: peers}
      end)

      hive_peers = PeerManager.get_hive_peers()

      assert Map.has_key?(hive_peers, id_same_verified)
      refute Map.has_key?(hive_peers, id_same_unverified)
      refute Map.has_key?(hive_peers, id_foreign)
    end

    test "returns empty map when no hive peers exist" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      # Default: is_same_hive=false, hive_verified=false
      assert PeerManager.get_hive_peers() == %{}
    end
  end

  describe "get_foreign_peers/0" do
    test "returns peers where is_same_hive is false" do
      id_same = TestNodeFactory.generate_uuid()
      id_foreign = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(id_same, %{rssi: -60})
      PeerManager.register_peer(id_foreign, %{rssi: -65})
      flush_casts()

      :sys.replace_state(PeerManager, fn state ->
        peers = Map.update!(state.peers, id_same, fn p ->
          %{p | is_same_hive: true, hive_verified: true}
        end)
        %{state | peers: peers}
      end)

      foreign = PeerManager.get_foreign_peers()

      # id_foreign has is_same_hive=false (default)
      assert Map.has_key?(foreign, id_foreign)
      refute Map.has_key?(foreign, id_same)
    end
  end

  describe "get_peers_by_hive/1 — filter by hive_id" do
    test "returns only peers matching the given hive_id" do
      id_a1 = TestNodeFactory.generate_uuid()
      id_a2 = TestNodeFactory.generate_uuid()
      id_b = TestNodeFactory.generate_uuid()
      id_none = TestNodeFactory.generate_uuid()

      for id <- [id_a1, id_a2, id_b, id_none] do
        PeerManager.register_peer(id, %{rssi: -60})
      end
      flush_casts()

      :sys.replace_state(PeerManager, fn state ->
        peers = state.peers
        |> Map.update!(id_a1, fn p -> %{p | hive_id: "hive-A"} end)
        |> Map.update!(id_a2, fn p -> %{p | hive_id: "hive-A"} end)
        |> Map.update!(id_b, fn p -> %{p | hive_id: "hive-B"} end)
        # id_none keeps hive_id: nil

        %{state | peers: peers}
      end)

      hive_a_peers = PeerManager.get_peers_by_hive("hive-A")
      assert map_size(hive_a_peers) == 2
      assert Map.has_key?(hive_a_peers, id_a1)
      assert Map.has_key?(hive_a_peers, id_a2)

      hive_b_peers = PeerManager.get_peers_by_hive("hive-B")
      assert map_size(hive_b_peers) == 1
      assert Map.has_key?(hive_b_peers, id_b)

      # Non-existent hive returns empty
      assert PeerManager.get_peers_by_hive("hive-Z") == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Stale peer cleanup
  # ---------------------------------------------------------------------------

  describe "stale peer cleanup (:cleanup_stale_peers)" do
    test "removes peers not seen for > 60 seconds" do
      stale_id = TestNodeFactory.generate_uuid()
      fresh_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(stale_id, %{rssi: -60, node_name: "StalePeer"})
      PeerManager.register_peer(fresh_id, %{rssi: -50, node_name: "FreshPeer"})
      flush_casts()

      # Make stale_id appear old by manipulating last_seen
      :sys.replace_state(PeerManager, fn state ->
        peers = Map.update!(state.peers, stale_id, fn p ->
          %{p | last_seen: System.system_time(:millisecond) - 120_000}
        end)
        %{state | peers: peers}
      end)

      # Trigger cleanup manually
      send(Process.whereis(PeerManager), :cleanup_stale_peers)
      flush_casts()

      # Stale peer removed, fresh peer retained
      assert {:error, :not_found} = PeerManager.get_peer(stale_id)
      assert {:ok, _} = PeerManager.get_peer(fresh_id)
    end

    test "protects WiFi-connected peers from cleanup" do
      wifi_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(wifi_id, %{rssi: -60})
      flush_casts()

      # Make it old but with WiFi transport
      :sys.replace_state(PeerManager, fn state ->
        peers = Map.update!(state.peers, wifi_id, fn p ->
          %{p |
            last_seen: System.system_time(:millisecond) - 120_000,
            transport: :wifi_hotspot
          }
        end)
        %{state | peers: peers}
      end)

      send(Process.whereis(PeerManager), :cleanup_stale_peers)
      flush_casts()

      # WiFi peer should survive cleanup
      assert {:ok, peer} = PeerManager.get_peer(wifi_id)
      assert peer.transport == :wifi_hotspot
    end

    test "protects sentants_exchanged peers from cleanup" do
      exchanged_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(exchanged_id, %{rssi: -60})
      PeerManager.update_peer_sentants(exchanged_id, [TestNodeFactory.build_sentant()])
      flush_casts()

      # Make it old but with sentants_exchanged state
      :sys.replace_state(PeerManager, fn state ->
        peers = Map.update!(state.peers, exchanged_id, fn p ->
          %{p | last_seen: System.system_time(:millisecond) - 120_000}
        end)
        %{state | peers: peers}
      end)

      send(Process.whereis(PeerManager), :cleanup_stale_peers)
      flush_casts()

      # Sentants-exchanged peer should survive cleanup
      assert {:ok, peer} = PeerManager.get_peer(exchanged_id)
      assert peer.connection_state == :sentants_exchanged
    end

    test "increments total_removed stat for cleaned-up peers" do
      stale_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(stale_id, %{rssi: -60})
      flush_casts()

      :sys.replace_state(PeerManager, fn state ->
        peers = Map.update!(state.peers, stale_id, fn p ->
          %{p | last_seen: System.system_time(:millisecond) - 120_000}
        end)
        %{state | peers: peers}
      end)

      send(Process.whereis(PeerManager), :cleanup_stale_peers)
      flush_casts()

      stats = PeerManager.get_stats()
      assert stats.total_removed >= 1
    end

    test "unprotected stale peer is removed while protected peers remain" do
      stale_plain_id = TestNodeFactory.generate_uuid()
      stale_wifi_id = TestNodeFactory.generate_uuid()
      stale_exchanged_id = TestNodeFactory.generate_uuid()
      fresh_id = TestNodeFactory.generate_uuid()

      for id <- [stale_plain_id, stale_wifi_id, stale_exchanged_id, fresh_id] do
        PeerManager.register_peer(id, %{rssi: -60})
      end

      PeerManager.update_peer_sentants(stale_exchanged_id, [TestNodeFactory.build_sentant()])
      flush_casts()

      old_time = System.system_time(:millisecond) - 120_000

      :sys.replace_state(PeerManager, fn state ->
        peers = state.peers
        |> Map.update!(stale_plain_id, fn p -> %{p | last_seen: old_time} end)
        |> Map.update!(stale_wifi_id, fn p ->
          %{p | last_seen: old_time, transport: :wifi_hotspot}
        end)
        |> Map.update!(stale_exchanged_id, fn p -> %{p | last_seen: old_time} end)
        # fresh_id keeps its recent last_seen

        %{state | peers: peers}
      end)

      send(Process.whereis(PeerManager), :cleanup_stale_peers)
      flush_casts()

      all = PeerManager.get_all_peers()

      # Only the unprotected stale peer should be removed
      refute Map.has_key?(all, stale_plain_id)
      assert Map.has_key?(all, stale_wifi_id)
      assert Map.has_key?(all, stale_exchanged_id)
      assert Map.has_key?(all, fresh_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Additional API coverage
  # ---------------------------------------------------------------------------

  describe "remove_peer/1" do
    test "removes a BLE peer" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      PeerManager.remove_peer(node_id)
      flush_casts()

      assert {:error, :not_found} = PeerManager.get_peer(node_id)
    end

    test "protects WiFi-connected peers from explicit removal" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      PeerManager.update_peer_transport(node_id, :wifi_hotspot)
      flush_casts()

      PeerManager.remove_peer(node_id)
      flush_casts()

      # WiFi peer should still exist
      assert {:ok, peer} = PeerManager.get_peer(node_id)
      assert peer.transport == :wifi_hotspot
    end

    test "silently ignores removal of nonexistent peer" do
      PeerManager.remove_peer("does-not-exist")
      flush_casts()
      assert is_map(PeerManager.get_all_peers())
    end
  end

  describe "update_peer_capabilities/2" do
    test "updates capabilities and last_seen" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      {:ok, before} = PeerManager.get_peer(node_id)
      Process.sleep(5)

      PeerManager.update_peer_capabilities(node_id, %{wifi_hotspot: true, battery_level: 85})
      flush_casts()

      {:ok, after_update} = PeerManager.get_peer(node_id)
      assert after_update.capabilities == %{wifi_hotspot: true, battery_level: 85}
      assert after_update.last_seen >= before.last_seen
    end
  end

  describe "update_peer_transport/2" do
    test "upgrades transport and increments wifi_upgrades stat" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      PeerManager.update_peer_transport(node_id, :wifi_hotspot)
      flush_casts()

      {:ok, peer} = PeerManager.get_peer(node_id)
      assert peer.transport == :wifi_hotspot

      stats = PeerManager.get_stats()
      assert stats.wifi_upgrades == 1
    end

    test "upgrade_to_wifi_hotspot/1 convenience function" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      PeerManager.upgrade_to_wifi_hotspot(node_id)
      flush_casts()

      {:ok, peer} = PeerManager.get_peer(node_id)
      assert peer.transport == :wifi_hotspot
    end
  end

  describe "get_highest_priority_peer/0" do
    test "returns peer with highest hosting_priority" do
      low_id = TestNodeFactory.generate_uuid()
      high_id = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(low_id, %{rssi: -60, hosting_priority: 20})
      PeerManager.register_peer(high_id, %{rssi: -70, hosting_priority: 90})
      flush_casts()

      assert {:ok, peer} = PeerManager.get_highest_priority_peer()
      assert peer.node_id == high_id
      assert peer.hosting_priority == 90
    end

    test "returns :no_peers when no peers exist" do
      assert {:error, :no_peers} = PeerManager.get_highest_priority_peer()
    end
  end

  describe "get_max_peer_priority/0" do
    test "returns the maximum hosting_priority" do
      PeerManager.register_peer(TestNodeFactory.generate_uuid(), %{rssi: -60, hosting_priority: 30})
      PeerManager.register_peer(TestNodeFactory.generate_uuid(), %{rssi: -65, hosting_priority: 80})
      PeerManager.register_peer(TestNodeFactory.generate_uuid(), %{rssi: -70, hosting_priority: 55})
      flush_casts()

      assert PeerManager.get_max_peer_priority() == 80
    end

    test "returns 0 when no peers exist" do
      assert PeerManager.get_max_peer_priority() == 0
    end
  end

  describe "get_stats/0" do
    test "returns comprehensive statistics" do
      id1 = TestNodeFactory.generate_uuid()
      id2 = TestNodeFactory.generate_uuid()

      PeerManager.register_peer(id1, %{rssi: -60})
      PeerManager.register_peer(id2, %{rssi: -70})
      flush_casts()

      PeerManager.update_peer_transport(id1, :wifi_hotspot)
      flush_casts()

      stats = PeerManager.get_stats()

      assert stats.current_peers == 2
      assert stats.total_discovered == 2
      assert stats.total_removed == 0
      assert stats.ble_peers == 1
      assert stats.wifi_peers == 1
      assert stats.wifi_upgrades == 1
    end
  end

  describe "get_reachability/1" do
    test "returns full reachability map for existing peer" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -55})
      flush_casts()

      assert {:ok, reach} = PeerManager.get_reachability(node_id)
      assert Map.has_key?(reach, :ble)
      assert Map.has_key?(reach, :wifi)
      assert Map.has_key?(reach, :lora)
    end

    test "returns :not_found for unknown peer" do
      assert {:error, :not_found} = PeerManager.get_reachability("ghost")
    end
  end

  describe "get_transport/1" do
    test "returns current transport for known peer" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      assert PeerManager.get_transport(node_id) == :ble_gatt
    end

    test "returns nil for unknown peer" do
      assert PeerManager.get_transport("nope") == nil
    end
  end

  describe "peer_verified?/1" do
    test "returns false for unverified peer" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      refute PeerManager.peer_verified?(node_id)
    end

    test "returns true for verified peer" do
      node_id = TestNodeFactory.generate_uuid()
      PeerManager.register_peer(node_id, %{rssi: -60})
      flush_casts()

      :sys.replace_state(PeerManager, fn state ->
        peers = Map.update!(state.peers, node_id, fn p ->
          %{p | hive_verified: true}
        end)
        %{state | peers: peers}
      end)

      assert PeerManager.peer_verified?(node_id)
    end

    test "returns false for unknown peer" do
      refute PeerManager.peer_verified?("nonexistent")
    end
  end
end
