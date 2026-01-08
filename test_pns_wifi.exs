#!/usr/bin/env elixir
# Test script for PNS Router and WiFi functionality
#
# Run with: mix run test_pns_wifi.exs

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("Reality2 PNS Router & WiFi Integration Test")
IO.puts(String.duplicate("=", 70) <> "\n")

# Give applications time to start
Process.sleep(2000)

# ============================================================================
# Test 1: PNS Router Status
# ============================================================================

IO.puts("TEST 1: PNS Router Status")
IO.puts(String.duplicate("-", 70))

case Process.whereis(AiReality2Pns.Router) do
  nil ->
    IO.puts("❌ FAIL: PNS Router not running")
    IO.puts("   Note: Ensure 'ai.reality2.pns' is in the PLUGINS environment variable\n")

  pid ->
    IO.puts("✅ PASS: PNS Router is running (#{inspect(pid)})")

    # Get routing table
    table = AiReality2Pns.Router.get_routing_table()
    IO.puts("   - Local Sentants: #{table.local_sentant_count}")
    IO.puts("   - Remote Sentants: #{table.remote_sentant_count}")
    IO.puts("   - Stats: #{inspect(table.stats)}\n")
end

# ============================================================================
# Test 2: WiFi NIF Availability
# ============================================================================

IO.puts("TEST 2: WiFi NIF Availability")
IO.puts(String.duplicate("-", 70))

# Check if the NIFs are loaded
wifi_nifs = [
  {:list_wifi_adapters_seq, 0},
  {:start_mesh, 3},
  {:stop_mesh, 1},
  {:get_mesh_peers, 2}
]

all_loaded = Enum.all?(wifi_nifs, fn {name, arity} ->
  case function_exported?(AiReality2Transnet.Action, name, arity) do
    true ->
      IO.puts("✅ PASS: #{name}/#{arity} is exported")
      true

    false ->
      IO.puts("❌ FAIL: #{name}/#{arity} is NOT exported")
      false
  end
end)

if all_loaded do
  IO.puts("\n✅ All WiFi NIFs are available\n")
else
  IO.puts("\n❌ Some WiFi NIFs are missing\n")
end

# ============================================================================
# Test 3: WiFi Adapter Listing
# ============================================================================

IO.puts("TEST 3: WiFi Adapter Listing")
IO.puts(String.duplicate("-", 70))

try do
  adapters = AiReality2Transnet.Action.list_wifi_adapters_seq()
  IO.puts("✅ PASS: list_wifi_adapters_seq() executed successfully")
  IO.puts("   Found #{length(adapters)} WiFi adapter(s):")

  Enum.each(adapters, fn adapter ->
    IO.puts("   - Interface: #{adapter.interface}")
    IO.puts("     Address: #{adapter.address}")
    IO.puts("     Mesh Interface: #{adapter.mesh_interface}")
  end)

  if Enum.empty?(adapters) do
    IO.puts("   ⚠️  Note: No WiFi adapters found (this is normal if running without WiFi hardware)\n")
  else
    IO.puts("")
  end
rescue
  error ->
    IO.puts("❌ FAIL: Error calling list_wifi_adapters_seq/0")
    IO.puts("   Error: #{inspect(error)}\n")
end

# ============================================================================
# Test 4: PNS Basic Functionality (if Router is running)
# ============================================================================

if Process.whereis(AiReality2Pns.Router) do
  IO.puts("TEST 4: PNS Basic Functionality")
  IO.puts(String.duplicate("-", 70))

  # Try to locate a non-existent Sentant
  fake_id = UUID.uuid4()

  case AiReality2Pns.Router.locate(fake_id) do
    {:error, :not_found} ->
      IO.puts("✅ PASS: Router correctly reports non-existent Sentant as not_found")

    other ->
      IO.puts("⚠️  Unexpected result: #{inspect(other)}")
  end

  # Get routing table stats
  table = AiReality2Pns.Router.get_routing_table()
  IO.puts("✅ PASS: Router.get_routing_table/0 works")
  IO.puts("   - Sentant locations cached: #{map_size(table.sentant_locations)}")
  IO.puts("   - Peer sentants tracked: #{map_size(table.peer_sentants)}\n")
else
  IO.puts("SKIP: Test 4 (PNS Router not running)\n")
end

# ============================================================================
# Summary
# ============================================================================

IO.puts(String.duplicate("=", 70))
IO.puts("Test Complete")
IO.puts(String.duplicate("=", 70))

IO.puts("""

Next Steps:
-----------
1. To start Reality2 Node with PNS and TransNet, use: ./run
2. Test PNS manually: AiReality2Pns.Test.quick_test()
3. Show routing table: AiReality2Pns.Test.show_routing_table()
4. List local Sentants: AiReality2Pns.Test.list_local_sentants()
5. List remote Sentants: AiReality2Pns.Test.list_remote_sentants()

Note: WiFi mesh requires root privileges to create mesh interfaces.
      Use 'sudo' if you need to start a WiFi mesh.
""")
