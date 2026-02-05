defmodule Mix.Tasks.R2.HardwareTest do
  @moduledoc """
  Mix task to run hardware integration tests for Reality2 Transient Networks.

  Tests are organized into phases, each adding more hardware:

    Phase 1: Laptop + 1 SBC (BLE discovery, WiFi cell, sentant exchange)
    Phase 2: + SBC2 (multi-peer mesh, relay)
    Phase 3: + Unihiker (4-node mesh, broadcast, trust group addressing)
    Phase 4: LoRa transport
    Phase 5: Cloud connectivity

  ## Usage

      mix r2.hardware_test              # Run all phases
      mix r2.hardware_test --phase 1    # Run phase 1 only
      mix r2.hardware_test --list       # List available phases
      mix r2.hardware_test --verbose    # Verbose output

  ## Environment Variables

      R2_SBC1_IP       SBC1 IP address (default: 192.168.4.2)
      R2_SBC2_IP       SBC2 IP address (default: 192.168.4.3)
      R2_UNIHIKER_IP   Unihiker IP address (default: 192.168.4.4)
      R2_CLOUD_URL     Cloud node URL (default: "")
  """

  use Mix.Task

  require Logger

  # WFS is a runtime dependency, not compile-time (same pattern as PeerManager)
  @compile {:no_warn_undefined, Reality2Wfs.Router}

  @shortdoc "Run hardware integration tests for Reality2 transnet"

  @phases %{
    1 => "Laptop + 1 SBC (BLE, WiFi, sentant exchange)",
    2 => "+ SBC2 (multi-peer mesh, relay)",
    3 => "+ Unihiker (4-node mesh, broadcast)",
    4 => "LoRa transport",
    5 => "Cloud connectivity"
  }

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  defp config do
    %{
      sbc1_ip: System.get_env("R2_SBC1_IP", "192.168.4.2"),
      sbc2_ip: System.get_env("R2_SBC2_IP", "192.168.4.3"),
      unihiker_ip: System.get_env("R2_UNIHIKER_IP", "192.168.4.4"),
      cloud_url: System.get_env("R2_CLOUD_URL", "")
    }
  end

  # ---------------------------------------------------------------------------
  # Entry point
  # ---------------------------------------------------------------------------

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      strict: [phase: :integer, list: :boolean, verbose: :boolean]
    )

    if opts[:list] do
      list_phases()
    else
      # Boot the application so GenServers are available
      Mix.Task.run("app.start")

      verbose = opts[:verbose] || false
      phase = opts[:phase]

      phases_to_run = if phase, do: [phase], else: Map.keys(@phases) |> Enum.sort()

      cfg = config()
      total_pass = :counters.new(1, [:atomics])
      total_fail = :counters.new(1, [:atomics])

      for p <- phases_to_run do
        if Map.has_key?(@phases, p) do
          run_phase(p, cfg, verbose, total_pass, total_fail)
        else
          Mix.shell().error("Unknown phase: #{p}. Use --list to see available phases.")
        end
      end

      pass_count = :counters.get(total_pass, 1)
      fail_count = :counters.get(total_fail, 1)
      total = pass_count + fail_count

      Mix.shell().info("")
      Mix.shell().info("=" |> String.duplicate(60))
      Mix.shell().info("RESULTS: #{pass_count}/#{total} passed, #{fail_count} failed")
      Mix.shell().info("=" |> String.duplicate(60))

      if fail_count > 0 do
        System.at_exit(fn _ -> exit({:shutdown, 1}) end)
      end
    end
  end

  defp list_phases do
    Mix.shell().info("Available hardware test phases:")
    Mix.shell().info("")

    for {num, desc} <- Enum.sort(@phases) do
      Mix.shell().info("  Phase #{num}: #{desc}")
    end

    Mix.shell().info("")
    Mix.shell().info("Usage: mix r2.hardware_test --phase <N>")
  end

  # ---------------------------------------------------------------------------
  # Phase runner
  # ---------------------------------------------------------------------------

  defp run_phase(phase_num, cfg, verbose, total_pass, total_fail) do
    desc = @phases[phase_num]
    Mix.shell().info("")
    Mix.shell().info("-" |> String.duplicate(60))
    Mix.shell().info("Phase #{phase_num}: #{desc}")
    Mix.shell().info("-" |> String.duplicate(60))

    results = case phase_num do
      1 -> phase_1(cfg, verbose)
      2 -> phase_2(cfg, verbose)
      3 -> phase_3(cfg, verbose)
      4 -> phase_4(cfg, verbose)
      5 -> phase_5(cfg, verbose)
    end

    for {label, result} <- results do
      case result do
        :pass ->
          :counters.add(total_pass, 1, 1)
          Mix.shell().info("  PASS  #{label}")

        {:fail, reason} ->
          :counters.add(total_fail, 1, 1)
          Mix.shell().error("  FAIL  #{label}: #{reason}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp test(label, fun) do
    try do
      case fun.() do
        :ok -> {label, :pass}
        {:ok, _} -> {label, :pass}
        true -> {label, :pass}
        {:error, reason} -> {label, {:fail, to_string(reason)}}
        false -> {label, {:fail, "returned false"}}
        other -> {label, {:fail, "unexpected: #{inspect(other)}"}}
      end
    rescue
      e -> {label, {:fail, Exception.message(e)}}
    catch
      :exit, reason -> {label, {:fail, "exit: #{inspect(reason)}"}}
    end
  end

  defp wait_for(timeout_ms, interval_ms, fun) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for(deadline, interval_ms, fun)
  end

  defp do_wait_for(deadline, interval_ms, fun) do
    case fun.() do
      {:ok, value} ->
        {:ok, value}

      true ->
        {:ok, true}

      _ ->
        now = System.monotonic_time(:millisecond)
        if now >= deadline do
          {:error, "timeout"}
        else
          Process.sleep(interval_ms)
          do_wait_for(deadline, interval_ms, fun)
        end
    end
  end

  defp http_get(url) do
    # Use httpoison with SSL verification disabled for self-signed certs
    case HTTPoison.get(url, [], [
      ssl: [verify: :verify_none],
      timeout: 10_000,
      recv_timeout: 10_000
    ]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, json} -> {:ok, json}
          _ -> {:ok, body}
        end

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  defp remote_info(ip) do
    http_get("https://#{ip}:4005/transnet/info")
  end

  defp verbose(true, msg), do: Mix.shell().info("       #{msg}")
  defp verbose(false, _msg), do: :ok

  # ---------------------------------------------------------------------------
  # Phase 1: Laptop + 1 SBC
  # ---------------------------------------------------------------------------

  defp phase_1(cfg, verbose?) do
    sbc1 = cfg.sbc1_ip

    [
      # 1. Local /transnet/info returns valid JSON
      test("Local /transnet/info returns valid JSON", fn ->
        case http_get("https://127.0.0.1:4005/transnet/info") do
          {:ok, %{"node_id" => _}} -> :ok
          {:ok, info} when is_map(info) ->
            verbose(verbose?, "Info: #{inspect(info)}")
            :ok
          other -> other
        end
      end),

      # 2. SBC1 /transnet/info reachable
      test("SBC1 /transnet/info reachable (#{sbc1})", fn ->
        case remote_info(sbc1) do
          {:ok, info} when is_map(info) ->
            verbose(verbose?, "SBC1 info: #{inspect(info)}")
            :ok
          other -> other
        end
      end),

      # 3. BLE discovery: PeerManager has >= 1 peer (poll 30s)
      test("BLE discovery: >= 1 peer in PeerManager (30s poll)", fn ->
        case wait_for(30_000, 2_000, fn ->
          peers = Reality2Transnet.PeerManager.get_all_peers()
          if length(peers) >= 1, do: {:ok, peers}, else: :waiting
        end) do
          {:ok, peers} ->
            verbose(verbose?, "Found #{length(peers)} peer(s)")
            :ok
          error -> error
        end
      end),

      # 4. WiFi cell: peer has transport :wifi_hotspot (poll 60s)
      test("WiFi cell: peer with wifi_hotspot transport (60s poll)", fn ->
        case wait_for(60_000, 2_000, fn ->
          peers = Reality2Transnet.PeerManager.get_all_peers()
          wifi_peer = Enum.find(peers, fn {_id, p} ->
            p[:transport] == :wifi_hotspot ||
              (p[:reachability] && p[:reachability][:wifi] && p[:reachability][:wifi][:confidence] > 0)
          end)
          if wifi_peer, do: {:ok, wifi_peer}, else: :waiting
        end) do
          {:ok, {id, _peer}} ->
            verbose(verbose?, "WiFi peer: #{id}")
            :ok
          {:ok, _} -> :ok
          error -> error
        end
      end),

      # 5. Sentant exchange: peer has non-empty sentants (poll 30s)
      test("Sentant exchange: peer has sentants (30s poll)", fn ->
        case wait_for(30_000, 2_000, fn ->
          peers = Reality2Transnet.PeerManager.get_all_peers()
          exchanged = Enum.find(peers, fn {_id, p} ->
            is_list(p[:sentants]) and length(p[:sentants]) > 0
          end)
          if exchanged, do: {:ok, exchanged}, else: :waiting
        end) do
          {:ok, {id, peer}} ->
            verbose(verbose?, "Peer #{id} has #{length(peer[:sentants])} sentant(s)")
            :ok
          error -> error
        end
      end),

      # 6. TrustGroupDirectory has >= 2 nodes
      test("TrustGroupDirectory has >= 2 nodes", fn ->
        directory = Reality2Transnet.TrustGroupDirectory.get_directory()
        node_count = if is_map(directory), do: map_size(directory), else: 0
        verbose(verbose?, "Directory has #{node_count} node(s)")
        if node_count >= 2, do: :ok, else: {:error, "only #{node_count} node(s)"}
      end),

      # 7. Local PingPong responds to ping
      test("Local PingPong responds to ping", fn ->
        case Reality2Wfs.Router.send_to_sentant("PingPong", "ping", %{}) do
          {:ok, _, _} -> :ok
          {:ok, _} -> :ok
          :ok -> :ok
          error -> {:error, "WFS send failed: #{inspect(error)}"}
        end
      end),

      # 8. Cross-node PingPong via WFS
      test("Cross-node PingPong via WFS", fn ->
        # Get the SBC node name from its info endpoint
        case remote_info(sbc1) do
          {:ok, %{"node_name" => sbc_name}} ->
            target = "#{sbc_name}|PingPong"
            verbose(verbose?, "Sending ping to #{target}")
            case Reality2Wfs.Router.send_to_sentant(target, "ping", %{}) do
              {:ok, _, _} -> :ok
              {:ok, _} -> :ok
              :ok -> :ok
              error -> {:error, "WFS cross-node send failed: #{inspect(error)}"}
            end
          {:ok, info} ->
            # Try alternate key formats
            sbc_name = info["name"] || info["node_name"] || "unknown"
            target = "#{sbc_name}|PingPong"
            case Reality2Wfs.Router.send_to_sentant(target, "ping", %{}) do
              {:ok, _, _} -> :ok
              {:ok, _} -> :ok
              :ok -> :ok
              error -> {:error, "WFS cross-node send failed: #{inspect(error)}"}
            end
          error -> {:error, "Cannot get SBC1 info: #{inspect(error)}"}
        end
      end)
    ]
  end

  # ---------------------------------------------------------------------------
  # Phase 2: + SBC2
  # ---------------------------------------------------------------------------

  defp phase_2(cfg, verbose?) do
    sbc2 = cfg.sbc2_ip

    [
      # 1. SBC2 reachable
      test("SBC2 reachable (#{sbc2})", fn ->
        case remote_info(sbc2) do
          {:ok, info} when is_map(info) ->
            verbose(verbose?, "SBC2 info: #{inspect(info)}")
            :ok
          other -> other
        end
      end),

      # 2. >= 2 peers in PeerManager (poll 30s)
      test(">= 2 peers in PeerManager (30s poll)", fn ->
        case wait_for(30_000, 2_000, fn ->
          peers = Reality2Transnet.PeerManager.get_all_peers()
          if length(peers) >= 2, do: {:ok, length(peers)}, else: :waiting
        end) do
          {:ok, count} ->
            verbose(verbose?, "#{count} peers found")
            :ok
          error -> error
        end
      end),

      # 3. >= 3 nodes in TrustGroupDirectory
      test(">= 3 nodes in TrustGroupDirectory", fn ->
        directory = Reality2Transnet.TrustGroupDirectory.get_directory()
        node_count = if is_map(directory), do: map_size(directory), else: 0
        verbose(verbose?, "Directory has #{node_count} node(s)")
        if node_count >= 3, do: :ok, else: {:error, "only #{node_count} node(s)"}
      end),

      # 4. Send to SBC2 sentant via WFS
      test("Send to SBC2 PingPong via WFS", fn ->
        case remote_info(sbc2) do
          {:ok, %{"node_name" => sbc2_name}} ->
            target = "#{sbc2_name}|PingPong"
            verbose(verbose?, "Sending ping to #{target}")
            case Reality2Wfs.Router.send_to_sentant(target, "ping", %{}) do
              {:ok, _, _} -> :ok
              {:ok, _} -> :ok
              :ok -> :ok
              error -> {:error, "WFS send to SBC2 failed: #{inspect(error)}"}
            end
          {:ok, info} ->
            sbc2_name = info["name"] || info["node_name"] || "unknown"
            target = "#{sbc2_name}|PingPong"
            case Reality2Wfs.Router.send_to_sentant(target, "ping", %{}) do
              {:ok, _, _} -> :ok
              {:ok, _} -> :ok
              :ok -> :ok
              error -> {:error, "WFS send to SBC2 failed: #{inspect(error)}"}
            end
          error -> {:error, "Cannot get SBC2 info: #{inspect(error)}"}
        end
      end),

      # 5. MeshRouter relay count > 0
      test("MeshRouter relay count > 0", fn ->
        stats = Reality2Transnet.MeshRouter.get_stats()
        relayed = stats[:messages_relayed] || stats["messages_relayed"] || 0
        verbose(verbose?, "MeshRouter stats: #{inspect(stats)}")
        if relayed > 0, do: :ok, else: {:error, "relayed: #{relayed}"}
      end),

      # 6. PeerManager stats check
      test("PeerManager stats valid", fn ->
        stats = Reality2Transnet.PeerManager.get_stats()
        verbose(verbose?, "PeerManager stats: #{inspect(stats)}")
        current = stats[:current_peers] || stats["current_peers"] || 0
        if current >= 2, do: :ok, else: {:error, "current_peers: #{current}"}
      end)
    ]
  end

  # ---------------------------------------------------------------------------
  # Phase 3: + Unihiker
  # ---------------------------------------------------------------------------

  defp phase_3(cfg, verbose?) do
    unihiker = cfg.unihiker_ip

    [
      # 1. Unihiker reachable
      test("Unihiker reachable (#{unihiker})", fn ->
        case remote_info(unihiker) do
          {:ok, info} when is_map(info) ->
            verbose(verbose?, "Unihiker info: #{inspect(info)}")
            :ok
          other -> other
        end
      end),

      # 2. 4 nodes in directory
      test("4 nodes in TrustGroupDirectory", fn ->
        directory = Reality2Transnet.TrustGroupDirectory.get_directory()
        node_count = if is_map(directory), do: map_size(directory), else: 0
        verbose(verbose?, "Directory has #{node_count} node(s)")
        if node_count >= 4, do: :ok, else: {:error, "only #{node_count} node(s)"}
      end),

      # 3. Broadcast "*" event delivered
      test("Broadcast \"*\" event delivered", fn ->
        case Reality2Wfs.Router.send_to_sentant("*", "ping", %{source: "hardware_test"}) do
          {:ok, %{local: l, remote: r}} ->
            verbose(verbose?, "Delivered to #{l} local, #{r} remote")
            :ok
          {:ok, _} -> :ok
          :ok -> :ok
          error -> {:error, "Broadcast failed: #{inspect(error)}"}
        end
      end),

      # 4. TrustGroup addressing resolves
      test("Trust group addressing resolves PingPong", fn ->
        case Reality2Wfs.Router.locate("*|PingPong") do
          {:ok, :multiple, locations} when is_list(locations) ->
            verbose(verbose?, "PingPong found at #{length(locations)} location(s)")
            if length(locations) >= 2, do: :ok, else: {:error, "only #{length(locations)} location(s)"}
          {:ok, _, _} -> :ok
          {:ok, _} -> :ok
          error -> {:error, "Locate failed: #{inspect(error)}"}
        end
      end)
    ]
  end

  # ---------------------------------------------------------------------------
  # Phase 4: LoRa
  # ---------------------------------------------------------------------------

  defp phase_4(_cfg, verbose?) do
    [
      # 1. LoRa serial device exists
      test("LoRa serial device exists (/dev/ttyACM*)", fn ->
        devices = Path.wildcard("/dev/ttyACM*")
        verbose(verbose?, "Serial devices: #{inspect(devices)}")
        if length(devices) > 0, do: :ok, else: {:error, "no /dev/ttyACM* device found"}
      end),

      # 2. LoRa peer in PeerManager (lora confidence > 0)
      test("LoRa peer in PeerManager (lora confidence > 0)", fn ->
        peers = Reality2Transnet.PeerManager.get_all_peers()
        lora_peer = Enum.find(peers, fn {_id, p} ->
          p[:reachability] && p[:reachability][:lora] && p[:reachability][:lora][:confidence] > 0
        end)
        if lora_peer do
          {id, _} = lora_peer
          verbose(verbose?, "LoRa peer: #{id}")
          :ok
        else
          {:error, "no peer with lora confidence > 0"}
        end
      end),

      # 3. Small event delivered via LoRa
      test("Small event delivered via LoRa", fn ->
        case Reality2Transnet.LoRaMesh.broadcast_event("hardware_test", "lora_ping", %{t: "test"}) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, :not_available} -> {:error, "LoRa not available"}
          error -> {:error, "LoRa send failed: #{inspect(error)}"}
        end
      end),

      # 4. MeshRouter transport_sends shows LoRa
      test("MeshRouter transport_sends shows LoRa", fn ->
        stats = Reality2Transnet.MeshRouter.get_stats()
        transport_sends = stats[:transport_sends] || stats["transport_sends"] || %{}
        lora_sends = transport_sends[:lora] || transport_sends["lora"] || 0
        verbose(verbose?, "Transport sends: #{inspect(transport_sends)}")
        if lora_sends > 0, do: :ok, else: {:error, "lora sends: #{lora_sends}"}
      end)
    ]
  end

  # ---------------------------------------------------------------------------
  # Phase 5: Cloud
  # ---------------------------------------------------------------------------

  defp phase_5(cfg, verbose?) do
    cloud_url = cfg.cloud_url

    if cloud_url == "" do
      [{"Cloud tests skipped (R2_CLOUD_URL not set)", {:fail, "set R2_CLOUD_URL env var"}}]
    else
      [
        # 1. Cloud node reachable via HTTP
        test("Cloud node reachable (#{cloud_url})", fn ->
          case http_get("#{cloud_url}/transnet/info") do
            {:ok, info} when is_map(info) ->
              verbose(verbose?, "Cloud info: #{inspect(info)}")
              :ok
            other -> other
          end
        end),

        # 2. Cloud peer with internet confidence > 0
        test("Cloud peer with internet confidence > 0", fn ->
          peers = Reality2Transnet.PeerManager.get_all_peers()
          cloud_peer = Enum.find(peers, fn {_id, p} ->
            p[:reachability] && p[:reachability][:internet] && p[:reachability][:internet][:confidence] > 0
          end)
          if cloud_peer do
            {id, peer} = cloud_peer
            confidence = peer[:reachability][:internet][:confidence]
            verbose(verbose?, "Cloud peer #{id}, confidence: #{confidence}")
            if confidence >= 200, do: :ok, else: {:error, "confidence only #{confidence}"}
          else
            {:error, "no peer with internet confidence > 0"}
          end
        end),

        # 3. Signal delivered to cloud sentant
        test("Signal delivered to cloud PingPong", fn ->
          case http_get("#{cloud_url}/transnet/info") do
            {:ok, %{"node_name" => cloud_name}} ->
              target = "#{cloud_name}|PingPong"
              verbose(verbose?, "Sending ping to #{target}")
              case Reality2Wfs.Router.send_to_sentant(target, "ping", %{}) do
                {:ok, _, _} -> :ok
                {:ok, _} -> :ok
                :ok -> :ok
                error -> {:error, "Cloud WFS send failed: #{inspect(error)}"}
              end
            {:ok, info} ->
              cloud_name = info["name"] || info["node_name"] || "unknown"
              target = "#{cloud_name}|PingPong"
              case Reality2Wfs.Router.send_to_sentant(target, "ping", %{}) do
                {:ok, _, _} -> :ok
                {:ok, _} -> :ok
                :ok -> :ok
                error -> {:error, "Cloud WFS send failed: #{inspect(error)}"}
              end
            error -> {:error, "Cannot get cloud info: #{inspect(error)}"}
          end
        end)
      ]
    end
  end
end
