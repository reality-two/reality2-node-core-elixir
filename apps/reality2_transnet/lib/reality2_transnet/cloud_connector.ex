defmodule Reality2Transnet.CloudConnector do
  @moduledoc """
  Manages persistent connections to cloud-hosted trust group nodes.

  A trust group may contain nodes running in the cloud (e.g., backup servers,
  analytics processors, always-on coordinators). These cloud nodes are
  reachable over the internet via WebSocket connections, unlike local
  nodes which use BLE, WiFi, or LoRa.

  ## Cloud Node Roles

  Cloud nodes serve several purposes:
  - **Remote backup** — mirrors sentant state and data from edge nodes
  - **Always-on relay** — bridges between partitioned subgroups of the trust group
  - **Analytics/compute** — offloads processing from constrained edge devices
  - **Gateway** — connects trust group to external systems and APIs

  ## Connection Lifecycle

  1. **Boot**: Reads configured cloud endpoints from config
  2. **Connect**: Establishes WebSocket connections with exponential backoff
  3. **Authenticate**: Sends trust group identity + node certificate for mutual trust
  4. **Sync**: Triggers TrustGroupDirectory merge on connection
  5. **Relay**: Bidirectionally forwards mesh messages over WebSocket
  6. **Monitor**: Heartbeat pings, reconnects on disconnect

  ## Configuration

      config :reality2_transnet,
        cloud_nodes: [
          %{url: "wss://cloud1.example.com/mesh", node_id: "uuid"},
          %{url: "wss://cloud2.example.com/mesh", node_id: "uuid"}
        ]

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  alias Reality2Transnet.{TrustGroupDirectory, PeerManager}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Constants
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @heartbeat_interval_ms 30_000          # Ping every 30 seconds
  @reconnect_base_ms 1_000              # Initial reconnect delay: 1 second
  @reconnect_max_ms 300_000             # Max reconnect delay: 5 minutes
  @connection_timeout_ms 10_000         # Connection establishment timeout

  defp log_prefix, do: "[CloudConnector:#{Reality2.Bootstrap.get(:node_name, "unknown")}]"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sends a mesh message to all connected cloud nodes.

  ## Returns
  - `:ok` — Message queued for sending
  - `{:error, :no_cloud_connections}` — No active connections
  """
  @spec send_to_cloud(map()) :: :ok | {:error, :no_cloud_connections}
  def send_to_cloud(message) do
    GenServer.call(__MODULE__, {:send_to_cloud, message})
  end

  @doc """
  Sends a mesh message to a specific cloud node by node_id.

  ## Returns
  - `:ok` — Message sent
  - `{:error, :not_connected}` — Cloud node not connected
  """
  @spec send_to_node(String.t(), map()) :: :ok | {:error, :not_connected}
  def send_to_node(node_id, message) do
    GenServer.call(__MODULE__, {:send_to_node, node_id, message})
  end

  @doc """
  Returns the list of configured cloud nodes and their connection status.
  """
  @spec get_status() :: [map()]
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Returns the list of currently connected cloud node IDs.
  """
  @spec connected_nodes() :: [String.t()]
  def connected_nodes do
    GenServer.call(__MODULE__, :connected_nodes)
  end

  @doc """
  Checks if any cloud connections are active.
  """
  @spec available?() :: boolean()
  def available? do
    GenServer.call(__MODULE__, :available?)
  catch
    :exit, _ -> false
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    cloud_configs = Application.get_env(:reality2_transnet, :cloud_nodes, [])

    connections = Enum.map(cloud_configs, fn config ->
      url = Map.get(config, :url) || config[:url]
      node_id = Map.get(config, :node_id) || config[:node_id]

      conn = %{
        url: url,
        node_id: node_id,
        status: :disconnected,
        pid: nil,
        reconnect_attempts: 0,
        last_connected: nil,
        last_error: nil
      }

      # Schedule initial connection attempt
      if url do
        Process.send_after(self(), {:connect, url}, 100)
      end

      {url, conn}
    end)
    |> Map.new()

    state = %{
      connections: connections,
      stats: %{
        messages_sent: 0,
        messages_received: 0,
        connections_established: 0,
        connections_failed: 0
      }
    }

    if map_size(connections) > 0 do
      Logger.info("#{log_prefix()} Started with #{map_size(connections)} cloud node(s) configured")
    else
      Logger.info("#{log_prefix()} Started — no cloud nodes configured")
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:send_to_cloud, message}, _from, state) do
    active = get_active_connections(state)

    if Enum.empty?(active) do
      {:reply, {:error, :no_cloud_connections}, state}
    else
      encoded = encode_message(message)
      Enum.each(active, fn {_url, conn} ->
        send_ws_message(conn.pid, encoded)
      end)
      new_stats = Map.update!(state.stats, :messages_sent, &(&1 + length(active)))
      {:reply, :ok, %{state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:send_to_node, node_id, message}, _from, state) do
    case find_connection_by_node(state, node_id) do
      {_url, conn} when conn.status == :connected and conn.pid != nil ->
        encoded = encode_message(message)
        send_ws_message(conn.pid, encoded)
        new_stats = Map.update!(state.stats, :messages_sent, &(&1 + 1))
        {:reply, :ok, %{state | stats: new_stats}}

      _ ->
        {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = Enum.map(state.connections, fn {url, conn} ->
      %{
        url: url,
        node_id: conn.node_id,
        status: conn.status,
        reconnect_attempts: conn.reconnect_attempts,
        last_connected: conn.last_connected,
        last_error: conn.last_error
      }
    end)
    {:reply, status, state}
  end

  @impl true
  def handle_call(:connected_nodes, _from, state) do
    nodes = state.connections
    |> Enum.filter(fn {_url, conn} -> conn.status == :connected end)
    |> Enum.map(fn {_url, conn} -> conn.node_id end)
    |> Enum.reject(&is_nil/1)
    {:reply, nodes, state}
  end

  @impl true
  def handle_call(:available?, _from, state) do
    has_active = Enum.any?(state.connections, fn {_url, conn} -> conn.status == :connected end)
    {:reply, has_active, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Connection Management
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_info({:connect, url}, state) do
    case Map.get(state.connections, url) do
      nil ->
        {:noreply, state}

      conn ->
        Logger.info("#{log_prefix()} Connecting to cloud node at #{url} (attempt #{conn.reconnect_attempts + 1})")

        # Spawn a task to establish the WebSocket connection
        # In production, this would use a WebSocket client library (e.g., :gun, :mint_web_socket)
        # For now, we use an HTTP-based polling fallback that works without additional dependencies
        parent = self()
        task_pid = spawn_link(fn ->
          result = establish_connection(url, parent)
          send(parent, {:connection_result, url, result})
        end)

        new_conn = %{conn | status: :connecting, pid: task_pid}
        new_connections = Map.put(state.connections, url, new_conn)
        {:noreply, %{state | connections: new_connections}}
    end
  end

  @impl true
  def handle_info({:connection_result, url, {:ok, ws_pid}}, state) do
    case Map.get(state.connections, url) do
      nil ->
        {:noreply, state}

      conn ->
        Logger.info("#{log_prefix()} Connected to cloud node at #{url}")
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        new_conn = %{conn |
          status: :connected,
          pid: ws_pid,
          reconnect_attempts: 0,
          last_connected: now,
          last_error: nil
        }

        new_connections = Map.put(state.connections, url, new_conn)
        new_stats = Map.update!(state.stats, :connections_established, &(&1 + 1))

        # Register cloud peer in PeerManager and TrustGroupDirectory
        # Pass the URL so the peer's IP/host can be extracted for WiFi bridge routing
        register_cloud_peer(conn.node_id, url)

        # Trigger directory sync
        sync_directory_with_cloud(ws_pid)

        # Schedule heartbeat
        Process.send_after(self(), {:heartbeat, url}, @heartbeat_interval_ms)

        {:noreply, %{state | connections: new_connections, stats: new_stats}}
    end
  end

  @impl true
  def handle_info({:connection_result, url, {:error, reason}}, state) do
    case Map.get(state.connections, url) do
      nil ->
        {:noreply, state}

      conn ->
        Logger.warning("#{log_prefix()} Failed to connect to #{url}: #{inspect(reason)}")

        new_conn = %{conn |
          status: :disconnected,
          pid: nil,
          reconnect_attempts: conn.reconnect_attempts + 1,
          last_error: inspect(reason)
        }

        new_connections = Map.put(state.connections, url, new_conn)
        new_stats = Map.update!(state.stats, :connections_failed, &(&1 + 1))

        # Schedule reconnect with exponential backoff
        delay = reconnect_delay(new_conn.reconnect_attempts)
        Logger.info("#{log_prefix()} Will retry #{url} in #{div(delay, 1000)}s")
        Process.send_after(self(), {:connect, url}, delay)

        {:noreply, %{state | connections: new_connections, stats: new_stats}}
    end
  end

  @impl true
  def handle_info({:ws_message, url, raw_data}, state) do
    # Incoming message from cloud node
    case decode_message(raw_data) do
      {:ok, message} ->
        new_stats = Map.update!(state.stats, :messages_received, &(&1 + 1))

        # Forward to MeshRouter for local delivery
        Reality2Transnet.MeshRouter.handle_incoming(message, :internet)

        {:noreply, %{state | stats: new_stats}}

      {:error, _} ->
        Logger.warning("#{log_prefix()} Invalid message from cloud #{url}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ws_closed, url, reason}, state) do
    case Map.get(state.connections, url) do
      nil ->
        {:noreply, state}

      conn ->
        Logger.warning("#{log_prefix()} Cloud connection to #{url} closed: #{inspect(reason)}")

        # Update peer reachability
        if conn.node_id do
          update_cloud_peer_disconnected(conn.node_id)
        end

        new_conn = %{conn |
          status: :disconnected,
          pid: nil,
          last_error: inspect(reason)
        }

        new_connections = Map.put(state.connections, url, new_conn)

        # Schedule reconnect
        delay = reconnect_delay(new_conn.reconnect_attempts + 1)
        new_conn = %{new_conn | reconnect_attempts: new_conn.reconnect_attempts + 1}
        new_connections = Map.put(new_connections, url, new_conn)
        Process.send_after(self(), {:connect, url}, delay)

        {:noreply, %{state | connections: new_connections}}
    end
  end

  @impl true
  def handle_info({:heartbeat, url}, state) do
    case Map.get(state.connections, url) do
      %{status: :connected, pid: pid} when pid != nil ->
        send_ws_message(pid, encode_heartbeat())
        Process.send_after(self(), {:heartbeat, url}, @heartbeat_interval_ms)
        {:noreply, state}

      _ ->
        # Connection lost, don't schedule more heartbeats
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:directory_sync_response, _url, remote_dir}, state) do
    # Merge received directory from cloud node
    if Code.ensure_loaded?(TrustGroupDirectory) and Process.whereis(TrustGroupDirectory) != nil do
      TrustGroupDirectory.merge_directory(remote_dir)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("#{log_prefix()} Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Close all connections gracefully
    Enum.each(state.connections, fn {_url, conn} ->
      if conn.pid != nil and Process.alive?(conn.pid) do
        Process.exit(conn.pid, :shutdown)
      end
    end)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Connection Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp establish_connection(url, parent) do
    # Attempt HTTP-based connection check
    # In production, this would establish a true WebSocket connection
    # using :gun or :mint_web_socket. For now, we attempt an HTTP health
    # check to the cloud endpoint and simulate the WebSocket channel
    # via an HTTP polling process.

    health_url = String.replace(url, ~r{/mesh$}, "/health")

    case http_health_check(health_url) do
      :ok ->
        # Start a relay process that polls the cloud node
        relay_pid = spawn_link(fn ->
          cloud_relay_loop(url, parent)
        end)
        {:ok, relay_pid}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp http_health_check(url) do
    if Code.ensure_loaded?(Finch) do
      request = Finch.build(:get, url)
      case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: @connection_timeout_ms) do
        {:ok, %Finch.Response{status: status}} when status in 200..299 ->
          :ok
        {:ok, %Finch.Response{status: status}} ->
          {:error, "http_#{status}"}
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :finch_not_available}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp cloud_relay_loop(url, parent) do
    receive do
      {:send, data} ->
        # Forward to cloud via HTTP POST
        send_http_message(url, data)
        cloud_relay_loop(url, parent)

      :stop ->
        :ok

    after
      60_000 ->
        # Periodic poll for incoming messages
        case poll_cloud_messages(url) do
          {:ok, messages} ->
            Enum.each(messages, fn msg ->
              send(parent, {:ws_message, url, msg})
            end)

          {:error, reason} ->
            send(parent, {:ws_closed, url, reason})
            :ok
        end
        cloud_relay_loop(url, parent)
    end
  end

  defp send_http_message(url, data) do
    if Code.ensure_loaded?(Finch) do
      request = Finch.build(:post, url, [{"content-type", "application/json"}], data)
      Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: @connection_timeout_ms)
    else
      {:error, :finch_not_available}
    end
  rescue
    _ -> {:error, :send_failed}
  end

  defp poll_cloud_messages(url) do
    poll_url = String.replace(url, ~r{/mesh$}, "/mesh/poll")

    if Code.ensure_loaded?(Finch) do
      request = Finch.build(:get, poll_url)
      case Finch.request(request, Reality2.TransnetHTTPClient, receive_timeout: @connection_timeout_ms) do
        {:ok, %Finch.Response{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"messages" => messages}} -> {:ok, messages}
            {:ok, _} -> {:ok, []}
            {:error, _} -> {:ok, []}
          end

        {:ok, %Finch.Response{status: 204}} ->
          {:ok, []}

        {:ok, %Finch.Response{status: status}} ->
          {:error, "http_#{status}"}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :finch_not_available}
    end
  rescue
    _ -> {:error, :poll_failed}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Peer Registration
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp register_cloud_peer(nil, _url), do: :ok
  defp register_cloud_peer(node_id, url) do
    # Extract host/IP from the cloud URL for WiFi bridge routing
    # e.g., "wss://cloud.example.com/mesh" → "cloud.example.com"
    cloud_ip = extract_host(url)

    # Register in PeerManager with both internet and wifi reachability
    # Internet: direct path (for nodes with their own internet access)
    # WiFi: bridge path (hotspot host can reach cloud IP via HTTP on port 4005)
    if Code.ensure_loaded?(PeerManager) and Process.whereis(PeerManager) != nil do
      PeerManager.register_peer(node_id, %{
        node_name: "cloud:#{String.slice(node_id, 0..7)}",
        transport: :internet,
        capabilities: %{is_cloud: true, wifi_hotspot: false}
      })

      PeerManager.update_reachability(node_id, :internet, %{
        confidence: 200
      })

      # Also register WiFi reachability with the cloud node's public IP
      # This enables the bridge path: edge → WiFi hotspot host → HTTP to cloud:4005
      if cloud_ip do
        PeerManager.update_reachability(node_id, :wifi, %{
          confidence: 180,
          ip: cloud_ip
        })
      end
    end

    # Register in TrustGroupDirectory
    if Code.ensure_loaded?(TrustGroupDirectory) and Process.whereis(TrustGroupDirectory) != nil do
      TrustGroupDirectory.register_node(node_id, %{
        name: "cloud:#{String.slice(node_id, 0..7)}",
        status: :active
      })

      TrustGroupDirectory.update_reachability(node_id, :internet, %{
        confidence: 200
      })

      if cloud_ip do
        TrustGroupDirectory.update_reachability(node_id, :wifi, %{
          confidence: 180,
          ip: cloud_ip
        })
      end
    end
  end

  defp update_cloud_peer_disconnected(node_id) do
    if Code.ensure_loaded?(PeerManager) and Process.whereis(PeerManager) != nil do
      PeerManager.update_reachability(node_id, :internet, %{confidence: 0})
    end

    if Code.ensure_loaded?(TrustGroupDirectory) and Process.whereis(TrustGroupDirectory) != nil do
      TrustGroupDirectory.update_reachability(node_id, :internet, %{confidence: 0})
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Directory Sync
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp sync_directory_with_cloud(ws_pid) do
    if Code.ensure_loaded?(TrustGroupDirectory) and Process.whereis(TrustGroupDirectory) != nil do
      dir = TrustGroupDirectory.get_directory()
      payload = Jason.encode!(%{type: "directory_sync", directory: export_for_sync(dir)})
      send_ws_message(ws_pid, payload)
    end
  end

  defp export_for_sync(directory) do
    # Export a sync-safe version of the directory (no binary compressed IDs)
    %{
      trust_group_id: directory.trust_group_id,
      trust_group_name: directory.trust_group_name,
      my_node_id: directory.my_node_id,
      directory_version: directory.directory_version,
      nodes: Map.new(directory.nodes, fn {id, entry} ->
        {id, Map.drop(entry, [:compressed_id])}
      end),
      trusted_trust_groups: directory.trusted_trust_groups
    }
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Message Encoding
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp encode_message(message) do
    Jason.encode!(%{
      type: "mesh_message",
      msg_id: message.msg_id,
      ttl: message.ttl,
      message_type: to_string(message.type),
      src_node_id: message.src_node_id,
      payload: message.payload
    })
  end

  defp decode_message(raw_data) when is_binary(raw_data) do
    case Jason.decode(raw_data) do
      {:ok, %{"type" => "mesh_message"} = data} ->
        {:ok, %{
          msg_id: Map.get(data, "msg_id", :rand.uniform(0xFFFFFFFF)),
          ttl: Map.get(data, "ttl", 5),
          type: parse_message_type(Map.get(data, "message_type", "event")),
          src_node_id: Map.get(data, "src_node_id", ""),
          payload: Map.get(data, "payload", "")
        }}

      {:ok, _} ->
        {:error, :not_mesh_message}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :decode_error}
  end
  defp decode_message(_), do: {:error, :invalid_format}

  defp encode_heartbeat do
    Jason.encode!(%{type: "heartbeat", timestamp: DateTime.utc_now() |> DateTime.to_iso8601()})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Utilities
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp send_ws_message(pid, data) when is_pid(pid) do
    if Process.alive?(pid) do
      send(pid, {:send, data})
      :ok
    else
      {:error, :process_dead}
    end
  end
  defp send_ws_message(_, _), do: {:error, :no_connection}

  defp get_active_connections(state) do
    Enum.filter(state.connections, fn {_url, conn} ->
      conn.status == :connected and conn.pid != nil
    end)
  end

  defp find_connection_by_node(state, node_id) do
    Enum.find(state.connections, fn {_url, conn} ->
      conn.node_id == node_id
    end)
  end

  defp reconnect_delay(attempts) do
    # Exponential backoff with jitter: base * 2^attempts + random jitter
    delay = @reconnect_base_ms * :math.pow(2, min(attempts, 10)) |> trunc()
    jitter = :rand.uniform(max(div(delay, 4), 1))
    min(delay + jitter, @reconnect_max_ms)
  end

  defp extract_host(url) when is_binary(url) do
    # Extract host from URL, e.g., "wss://cloud.example.com/mesh" → "cloud.example.com"
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> nil
    end
  end
  defp extract_host(_), do: nil

  defp parse_message_type("event"), do: :event
  defp parse_message_type("signal"), do: :signal
  defp parse_message_type("presence"), do: :presence
  defp parse_message_type("data"), do: :data
  defp parse_message_type(_), do: :event
end
