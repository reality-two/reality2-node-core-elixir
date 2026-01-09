defmodule AiReality2Transnet.WifiServer do
  @moduledoc """
  WiFi Mesh GraphQL Server for Reality2 Transient Networks.

  This module implements an HTTP/GraphQL server that runs on WiFi mesh interfaces,
  enabling Reality2 nodes to query each other's Sentant capabilities and send commands
  in a peer-to-peer fashion.

  ## Architecture Overview

  Reality2's transient networking uses a **layered approach**:

  ```
  ┌──────────────────────────────────────────────────┐
  │  Layer 1: BLE Discovery (Always On, Low Power)   │
  │  - Beacon broadcasting                            │
  │  - Device scanning                                │
  │  - Presence detection                             │
  │  - Limited to ~512 bytes                          │
  └──────────────────────────────────────────────────┘
                        ↓
  ┌──────────────────────────────────────────────────┐
  │  Layer 2: WiFi Mesh (On-Demand, High Bandwidth)  │
  │  - IEEE 802.11s mesh networking                   │
  │  - IPv6 link-local addressing                     │
  │  - Multi-hop routing (HWMP)                       │
  └──────────────────────────────────────────────────┘
                        ↓
  ┌──────────────────────────────────────────────────┐
  │  Layer 3: This Module (GraphQL over HTTP)        │
  │  - Query remote Sentants (sentantAll)             │
  │  - Send events to remote Sentants (sentantSend)   │
  │  - Subscribe to signals (awaitSignal - future)    │
  │  - Privacy filtering for transient peers          │
  └──────────────────────────────────────────────────┘
  ```

  ## Why GraphQL?

  Instead of a custom RPC protocol, Reality2 uses **GraphQL** for consistency:

  - **Same schema** as main API (port 4005) - ensures identical behavior
  - **Self-documenting** - peers can introspect available operations
  - **Standard tooling** - debug with GraphiQL, Insomnia, curl, etc.
  - **Future-proof** - easy to add fields without breaking compatibility

  ## Consolidated HTTP on Port 4005

  All HTTP/GraphQL endpoints are now served via Reality2Web on **port 4005**.

  **Mesh-specific endpoints:**
  - `GET /mesh/sentants` - List all Sentants (public info only)
  - `GET /mesh/info` - Node info and mesh status
  - `POST /reality2` - GraphQL endpoint (same as main API)

  **Privacy model:** All responses expose only public information (name, events, signals).

  ## Sentant Lifecycle

  Sentants can be created/deleted in two ways:

  1. **At Startup** - Sentants loaded from configuration (always available)
  2. **Dynamically via GraphQL** - Only if environment variable permits:
     - Node is "open": Sentants can be created/deleted via GraphQL
     - Node is "closed": Sentants are startup-only, no dynamic changes

  Transient peer queries via /mesh/* endpoints are read-only.

  ## Sentant Design Principles: IPUC

  Sentants follow the **IPUC model**, which fundamentally shapes their architecture:

  - **Immutable** - Once a Sentant exists, its definition cannot be changed
  - **Persistent** - Sentants persist across restarts and system changes
  - **Unique** - Each Sentant has a globally unique identifier (UUID)
  - **Consistent** - Same view of a Sentant from any interface or protocol

  ### Immutability and Plugins

  **Sentants are immutable definitions**, not mutable data structures:
  - A Sentant's interface (events, signals) is fixed at creation
  - Sentants cannot be "modified" or "updated" after creation
  - Sentants CAN interact with mutable data through **plugins**
  - Plugins allow Sentants to read/write external state while remaining immutable themselves

  This immutability is why deletion is separate from modification - you can only create
  or delete a Sentant, never change it.

  ## Privacy Model - Sentants Are Opaque

  **Sentants are designed to be opaque** - they expose their public interface (capabilities),
  but hide their internal implementation (state, parameters, definitions).

  This opacity follows naturally from the IPUC model: since Sentants are immutable
  definitions, what you expose is a consistent, unchanging public interface.

  **GraphQL in Reality2 is designed to ONLY expose public information**, regardless of port.

  All endpoints follow the same privacy model:

  ### ✅ Public Information Exposed

  - **Sentant ID** - UUID for addressing
  - **Sentant Name** - Human-readable identifier
  - **Event Names** - Commands that can be sent (e.g., "read", "calibrate")
  - **Signal Names** - Notifications that can be received (e.g., "value_changed")

  ### ❌ Private Information Filtered Out

  - **Sentant State** - Current values, internal data
  - **Parameters** - Event/signal parameter types and descriptions
  - **Full Definitions** - Complete schema and structure
  - **User Information** - Ownership, permissions, metadata

  ### Why This Model?

  **Sentants are designed with privacy-first architecture:**

  The GraphQL API exposes the **"what you can do"** (capabilities), not **"what you are"** (state).

  This allows:
  - ✅ Discovering what capabilities a node has ("Can you measure temperature?")
  - ✅ Sending public events to trigger actions ("Please take a reading")
  - ✅ Receiving public signals about state changes ("Temperature changed")

  But never exposes:
  - ❌ Current sensor values or internal state
  - ❌ Internal configurations or parameters
  - ❌ User information or ownership
  - ❌ Implementation details or full schemas

  This is especially important for **transient networks** (WiFi mesh between strangers):
  ```
  Your wearable ←→ Random person's wearable
      (WiFi mesh)
  ```

  Even between strangers, you can safely interact with capabilities without leaking private data.

  ## Server Architecture

  This module is a **GenServer** that manages WiFi mesh operations:
  1. Checks for WiFi adapters and mesh capabilities
  2. Provides mesh management commands (create/destroy mesh, list peers)
  3. Provides client API for querying remote peers via HTTP
  4. HTTP endpoints are served by Reality2Web on port 4005

  ## GraphQL Endpoints

  ### Query: `sentantAll`

  Returns **public interface** of all Sentants on this node.

  ```graphql
  query {
    sentantAll {
      id         # UUID for addressing
      name       # Human-readable name
      events     # ["read", "calibrate"] - names only, no parameters
      signals    # ["temperature_changed"] - names only, no parameters
    }
  }
  ```

  **Response (privacy filtered):**
  ```json
  {
    "data": {
      "sentantAll": [
        {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "name": "temperature_sensor",
          "events": ["read", "calibrate"],
          "signals": ["temperature_changed"]
        }
      ]
    }
  }
  ```

  ### Mutation: `sentantSend`

  Sends an **event** (command) to a Sentant.

  ```graphql
  mutation {
    sentantSend(
      id: "550e8400-e29b-41d4-a716-446655440000"
      event: "read"
      parameters: "{\"unit\":\"celsius\"}"
    ) {
      id
      name
    }
  }
  ```

  **Response (privacy filtered):**
  ```json
  {
    "data": {
      "sentantSend": {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "temperature_sensor"
      }
    }
  }
  ```

  **Note:** Response does NOT include:
  - State changes
  - Return values
  - Internal results

  The event is executed, but response is intentionally minimal for privacy.

  ### Subscription: `awaitSignal` (Future Feature)

  Will allow real-time signal subscriptions over WebSockets.

  ```graphql
  subscription {
    awaitSignal(id: "sentant-uuid", signal: "temperature_changed") {
      signal
      data  # Filtered to public data only
    }
  }
  ```

  ## Usage Examples

  ### Start Manager

  ```elixir
  # WifiServer starts automatically as part of ai_reality2_transnet supervision tree
  # HTTP endpoints are served via Reality2Web on port 4005

  # Check status
  AiReality2Transnet.WifiServer.get_status()
  # => %{status: :ready, adapters: [...]}
  ```

  ### Query Remote Peer

  ```elixir
  # Get peer's IPv6 address from WiFi mesh
  {:ok, peer_ipv6} = AiReality2Transnet.Wifi.get_ipv6_link_local("mesh0")
  # => "fe80::aabb:ccff:fedd:eeff"

  # Query peer's sentants
  {:ok, sentants} = AiReality2Transnet.WifiServer.query_peer_sentants(peer_ipv6)
  # => [%{"id" => "...", "name" => "sensor1", "events" => ["read"], ...}]
  ```

  ### Send Event to Remote Peer

  ```elixir
  peer_ipv6 = "fe80::aabb:ccff:fedd:eeff"
  sentant_id = "550e8400-e29b-41d4-a716-446655440000"

  {:ok, result} = AiReality2Transnet.WifiServer.send_to_peer(
    peer_ipv6,
    sentant_id,
    "read",
    %{unit: "celsius"}
  )
  # => %{"id" => "...", "name" => "temperature_sensor"}
  ```

  ### Test with curl

  ```bash
  # Query sentants (simple REST endpoint)
  curl "http://[fe80::peer-ipv6%mesh0]:4005/mesh/sentants"

  # Query node info
  curl "http://[fe80::peer-ipv6%mesh0]:4005/mesh/info"

  # GraphQL query
  curl -X POST "http://[fe80::peer-ipv6%mesh0]:4005/reality2" \
    -H "Content-Type: application/json" \
    -d '{"query": "query { sentantAll { id name events signals } }"}'

  # GraphQL mutation (send event)
  curl -X POST "http://[fe80::peer-ipv6%mesh0]:4005/reality2" \
    -H "Content-Type: application/json" \
    -d '{
      "query": "mutation($id: ID!, $event: String!, $parameters: String) { sentantSend(id: $id, event: $event, parameters: $parameters) { id name } }",
      "variables": {
        "id": "sentant-uuid",
        "event": "read",
        "parameters": "{\"unit\":\"celsius\"}"
      }
    }'
  ```

  ## Security Considerations

  ### Threat Model

  **WiFi Mesh = Semi-Trusted Environment:**
  - Same mesh ID implies coordination (negotiated via BLE)
  - Not open internet, but not fully trusted either
  - Analogous to corporate WiFi or conference WiFi

  ### Attacks Prevented ✅

  - **State Inspection** - Only events exposed, no state readable
  - **Data Exfiltration** - No state in responses, only acknowledgments
  - **Structure Probing** - Parameters hidden, can't discover internal schema

  ### Attacks NOT Prevented ⚠️

  - **Event Spamming** - Can send many events rapidly (add rate limiting)
  - **Signal Enumeration** - Can see signal names (by design, part of public API)
  - **Timing Attacks** - Response times might leak information

  ### Future Mitigations

  - Rate limiting per peer
  - Event validation (already done by Sentants)
  - Audit logging
  - Reputation system

  ## Related Modules

  - `AiReality2Transnet.Wifi` - WiFi mesh interface management
  - `AiReality2Transnet.Bluetooth` - BLE discovery layer
  - `AiReality2Transnet.PeerManager` - Tracks discovered peers
  - `Reality2Web.Schema` - GraphQL schema (reused here with filtering)

  ## Configuration

  Server port is configurable via module attribute (default: 4005).

  ## Further Reading

  - GraphQL Spec: https://graphql.org/
  - Absinthe (Elixir GraphQL): https://hexdocs.pm/absinthe/
  - Cowboy HTTP Server: https://ninenines.eu/docs/en/cowboy/
  - Plug: https://hexdocs.pm/plug/

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  # Suppress warnings for optional GraphQL integration (runtime checks used)
  # Absinthe and Reality2Web.Schema may not be available in all configurations
  # We use Code.ensure_loaded?/1 and fallback to simplified implementation
  @compile {:no_warn_undefined, [Absinthe, Reality2Web.Schema]}

  # Use same port as Reality2Web (consolidate all HTTP on one port)
  @default_port 4005

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Gets the server status and statistics.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Queries sentants on a remote peer via WiFi mesh using GraphQL.

  ## Parameters
  - `peer_ipv6` - IPv6 link-local address of the peer
  - `port` - HTTP port (default 4005)

  ## Returns
  - `{:ok, sentants}` - List of public sentant info (name, events, signals)
  - `{:error, reason}` - Failed to query
  """
  def query_peer_sentants(peer_ipv6, port \\ @default_port) do
    url = "http://[#{peer_ipv6}]:#{port}/reality2"

    query = """
    query {
      sentantAll {
        id
        name
        events
        signals
      }
    }
    """

    body = Jason.encode!(%{query: query})
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, body, headers, recv_timeout: 5000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => %{"sentantAll" => sentants}}} -> {:ok, sentants}
          {:ok, %{"errors" => errors}} -> {:error, {:graphql_errors, errors}}
          {:ok, _} -> {:error, :invalid_response}
          {:error, reason} -> {:error, {:json_decode_failed, reason}}
        end

      {:ok, %{status_code: code}} ->
        {:error, {:http_error, code}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Sends a command to a remote Sentant via WiFi mesh using GraphQL.

  ## Parameters
  - `peer_ipv6` - IPv6 link-local address of the peer
  - `sentant_id` - Target Sentant UUID
  - `event` - Event name
  - `parameters` - Event parameters (default: %{})
  - `passthrough` - Passthrough data (default: nil)
  - `port` - HTTP port (default 4005)

  ## Returns
  - `{:ok, response}` - Command succeeded
  - `{:error, reason}` - Command failed
  """
  def send_to_peer(peer_ipv6, sentant_id, event, parameters \\ %{}, passthrough \\ nil, port \\ @default_port) do
    url = "http://[#{peer_ipv6}]:#{port}/reality2"

    # GraphQL mutation
    query = """
    mutation($id: ID!, $event: String!, $parameters: String, $passthrough: String) {
      sentantSend(id: $id, event: $event, parameters: $parameters, passthrough: $passthrough) {
        id
        name
      }
    }
    """

    variables = %{
      id: sentant_id,
      event: event,
      parameters: Jason.encode!(parameters),
      passthrough: if(passthrough, do: Jason.encode!(passthrough), else: nil)
    }

    body = Jason.encode!(%{query: query, variables: variables})
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, body, headers, recv_timeout: 5000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => %{"sentantSend" => result}}} -> {:ok, result}
          {:ok, %{"errors" => errors}} -> {:error, {:graphql_errors, errors}}
          {:ok, _} -> {:error, :invalid_response}
          {:error, reason} -> {:error, {:json_decode_failed, reason}}
        end

      {:ok, %{status_code: code, body: body}} ->
        {:error, {:http_error, code, body}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Check system dependencies first
    case AiReality2Transnet.Wifi.check_dependencies() do
      {:error, missing} ->
        Logger.error("[WifiServer] Missing required system commands:")

        Enum.each(missing, fn cmd ->
          Logger.error("  - #{cmd.command} not found")
          Logger.error("    Install: #{cmd.debian} (Debian/Ubuntu)")
          Logger.error("           #{cmd.fedora} (Fedora/RHEL)")
          Logger.error("           #{cmd.arch} (Arch Linux)")
        end)

        {:ok, %{status: :missing_dependencies, missing: missing}}

      {:ok, :all_available} ->
        # Check if WiFi adapters are available
        case AiReality2Transnet.Wifi.list_adapters() do
          {:ok, [_ | _] = adapters} ->
            # HTTP is now handled by Reality2Web on port 4005
            # This GenServer only manages WiFi mesh operations
            state = %{
              status: :ready,
              started_at: DateTime.utc_now(),
              adapters: adapters
            }

            Logger.info("[WifiServer] WiFi mesh manager started")
            Logger.info("[WifiServer] Found #{length(adapters)} WiFi adapter(s)")
            Logger.info("[WifiServer] HTTP endpoints available via Reality2Web on port 4005")
            {:ok, state}

          {:ok, []} ->
            Logger.warning("[WifiServer] No WiFi adapters available")
            Logger.info("[WifiServer] WiFi mesh functionality will be unavailable")
            {:ok, %{status: :no_wifi}}

          {:error, reason} ->
            Logger.error("[WifiServer] Failed to list WiFi adapters: #{inspect(reason)}")
            {:ok, %{status: :error, reason: reason}}
        end
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_mesh_info, _from, state) do
    mesh_info = get_mesh_info_internal()
    {:reply, {:ok, mesh_info}, state}
  end

  @impl true
  def handle_cast({:record_request, success}, state) do
    new_state =
      if success do
        %{state | requests_handled: state.requests_handled + 1}
      else
        %{state | errors: state.errors + 1}
      end

    {:noreply, new_state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Command Handlers (from Sentant automations via Main.sendto)
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_cast(%{command: "list_adapters"}, state) do
    Logger.debug("[WifiServer] Listing WiFi adapters")

    case AiReality2Transnet.Wifi.list_adapters() do
      {:ok, adapters} ->
        Logger.info("[WifiServer] Found #{length(adapters)} WiFi adapters")
        # TODO: Signal back to Sentant with results
        {:noreply, state}

      {:error, reason} ->
        Logger.error("[WifiServer] Failed to list adapters: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(%{command: "create_mesh", parameters: params}, state) do
    interface = Map.get(params, "interface") || Map.get(params, :interface)
    mesh_interface = Map.get(params, "mesh_interface") || Map.get(params, :mesh_interface, "mesh0")
    mesh_id = Map.get(params, "mesh_id") || Map.get(params, :mesh_id)
    frequency = Map.get(params, "frequency") || Map.get(params, :frequency, 2437)

    Logger.info("[WifiServer] Creating mesh: #{mesh_interface} from #{interface}, ID: #{mesh_id}, freq: #{frequency}")

    with {:ok, _} <- AiReality2Transnet.Wifi.create_mesh_interface(interface, mesh_interface),
         {:ok, _} <- AiReality2Transnet.Wifi.start_mesh(mesh_interface, mesh_id, frequency) do
      Logger.info("[WifiServer] Mesh created successfully")
      {:noreply, state}
    else
      {:error, reason} ->
        Logger.error("[WifiServer] Failed to create mesh: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(%{command: "destroy_mesh", parameters: params}, state) do
    mesh_interface = Map.get(params, "mesh_interface") || Map.get(params, :mesh_interface, "mesh0")

    Logger.info("[WifiServer] Destroying mesh interface: #{mesh_interface}")

    case AiReality2Transnet.Wifi.destroy_mesh_interface(mesh_interface) do
      :ok ->
        Logger.info("[WifiServer] Mesh destroyed successfully")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("[WifiServer] Failed to destroy mesh: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(%{command: "list_peers", parameters: params}, state) do
    mesh_interface = Map.get(params, "mesh_interface") || Map.get(params, :mesh_interface, "mesh0")

    Logger.debug("[WifiServer] Listing mesh peers on #{mesh_interface}")

    case AiReality2Transnet.Wifi.list_mesh_peers(mesh_interface) do
      {:ok, peers} ->
        Logger.info("[WifiServer] Found #{length(peers)} mesh peers")
        # TODO: Signal back to Sentant with results
        {:noreply, state}

      {:error, reason} ->
        Logger.error("[WifiServer] Failed to list peers: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(%{command: "get_ipv6", parameters: params}, state) do
    interface = Map.get(params, "interface") || Map.get(params, :interface, "mesh0")

    Logger.debug("[WifiServer] Getting IPv6 address for #{interface}")

    case AiReality2Transnet.Wifi.get_ipv6_link_local(interface) do
      {:ok, ipv6} ->
        Logger.info("[WifiServer] IPv6 address: #{ipv6}")
        # TODO: Signal back to Sentant with results
        {:noreply, state}

      {:error, reason} ->
        Logger.error("[WifiServer] Failed to get IPv6: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  # Get mesh network info for the MeshController
  defp get_mesh_info_internal do
    case AiReality2Transnet.Wifi.list_adapters() do
      {:ok, adapters} ->
        mesh_adapter = Enum.find(adapters, fn adapter ->
          Map.get(adapter, :mesh_interface) != nil
        end)

        if mesh_adapter do
          case AiReality2Transnet.Wifi.get_ipv6_link_local(mesh_adapter.mesh_interface) do
            {:ok, ipv6} ->
              %{
                active: true,
                mesh_id: "R2MESH",
                interface: mesh_adapter.mesh_interface,
                ipv6_link_local: ipv6
              }

            {:error, _} ->
              %{
                active: true,
                mesh_id: "R2MESH",
                interface: mesh_adapter.mesh_interface,
                ipv6_link_local: nil
              }
          end
        else
          %{active: false}
        end

      {:error, _} ->
        %{active: false}
    end
  end
end

# -----------------------------------------------------------------------------------------------------------------------------------------
# HTTP Router using Plug (Legacy - kept for reference, no longer started)
# -----------------------------------------------------------------------------------------------------------------------------------------

defmodule AiReality2Transnet.WifiServer.Router do
  use Plug.Router
  require Logger

  # Suppress warnings for optional GraphQL integration (runtime checks used)
  # Absinthe and Reality2Web.Schema may not be available in all configurations
  @compile {:no_warn_undefined, [Absinthe, Reality2Web.Schema]}

  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:match)
  plug(:dispatch)

  # POST /graphql - GraphQL endpoint (matches main Reality2 API)
  post "/graphql" do
    case conn.body_params do
      %{"query" => query} ->
        variables = Map.get(conn.body_params, "variables", %{})
        handle_graphql_query(conn, query, variables)

      _ ->
        error_response = %{
          errors: [%{message: "Missing query parameter"}]
        }
        send_json_response(conn, 400, error_response)
        record_request(false)
    end
  end

  # Legacy REST endpoint for simple queries
  get "/sentants" do
    node_id = Reality2.Bootstrap.get(:node_id)
    sentants = get_public_sentant_info()

    response = %{
      node_id: node_id,
      sentant_count: length(sentants),
      sentants: sentants,
      timestamp: System.system_time(:millisecond)
    }

    send_json_response(conn, 200, response)
    record_request(true)
  end

  # GET /info - Query node info
  get "/info" do
    node_id = Reality2.Bootstrap.get(:node_id)

    # Get mesh info
    mesh_info = get_mesh_info()

    response = %{
      node_id: node_id,
      version: "0.1.13",
      capabilities: %{
        bluetooth: true,
        wifi_mesh: wifi_available?(),
        sentants: Reality2.Metadata.all(:SentantIDs) |> map_size()
      },
      mesh_info: mesh_info,
      timestamp: System.system_time(:millisecond)
    }

    send_json_response(conn, 200, response)
    record_request(true)
  end

  # Fallback for unknown routes
  match _ do
    error_response = %{
      error: "not_found",
      message: "Endpoint not found",
      timestamp: System.system_time(:millisecond)
    }

    send_json_response(conn, 404, error_response)
    record_request(false)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GraphQL Handler
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp handle_graphql_query(conn, query, variables) do
    # Use the existing Reality2 GraphQL schema via Absinthe
    # This ensures consistency with the main GraphQL API on port 4005

    if Code.ensure_loaded?(Absinthe) && Code.ensure_loaded?(Reality2Web.Schema) do
      # Execute query using existing schema
      case Absinthe.run(query, Reality2Web.Schema, variables: variables) do
        {:ok, %{data: data, errors: errors}} when errors != nil and errors != [] ->
          response = %{data: data, errors: errors}
          send_json_response(conn, 200, response)
          record_request(false)

        {:ok, %{data: data}} ->
          # Filter response to only include public information
          filtered_data = filter_private_data(data)
          response = %{data: filtered_data}
          send_json_response(conn, 200, response)
          record_request(true)

        {:error, error} ->
          response = %{errors: [%{message: inspect(error)}]}
          send_json_response(conn, 400, response)
          record_request(false)
      end
    else
      # Fallback: Use simplified public-only implementation
      handle_graphql_query_fallback(conn, query, variables)
    end
  end

  # Filter response data to only include public information (name, events, signals)
  defp filter_private_data(%{"sentantAll" => sentants}) when is_list(sentants) do
    %{"sentantAll" => Enum.map(sentants, &filter_sentant_data/1)}
  end

  defp filter_private_data(%{"sentantSend" => sentant}) when is_map(sentant) do
    %{"sentantSend" => filter_sentant_data(sentant)}
  end

  defp filter_private_data(data), do: data

  # Keep only public fields from Sentant data
  defp filter_sentant_data(sentant) when is_map(sentant) do
    sentant
    |> Map.take(["id", "name", "events", "signals"])
    |> Map.update("events", [], fn events ->
      # Extract just event names if events are objects
      Enum.map(events, fn
        %{"name" => name} -> name
        %{"event" => name} -> name
        name when is_binary(name) -> name
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
    end)
    |> Map.update("signals", [], fn signals ->
      # Extract just signal names if signals are objects
      Enum.map(signals, fn
        %{"name" => name} -> name
        %{"signal" => name} -> name
        name when is_binary(name) -> name
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp filter_sentant_data(sentant), do: sentant

  # Fallback implementation if Reality2Web.Schema not available
  defp handle_graphql_query_fallback(conn, query, variables) do
    Logger.warning("[WifiServer] Reality2Web.Schema not available, using fallback")

    cond do
      String.contains?(query, "sentantAll") ->
        sentants = get_public_sentant_info()
        response = %{data: %{sentantAll: sentants}}
        send_json_response(conn, 200, response)
        record_request(true)

      String.contains?(query, "sentantSend") ->
        handle_sentant_send_fallback(conn, variables)

      true ->
        response = %{errors: [%{message: "Unknown query or mutation"}]}
        send_json_response(conn, 400, response)
        record_request(false)
    end
  end

  defp handle_sentant_send_fallback(conn, variables) do
    sentant_id = Map.get(variables, "id")
    event = Map.get(variables, "event")
    parameters = Map.get(variables, "parameters", %{})
    passthrough = Map.get(variables, "passthrough")

    case Reality2.Sentants.sendto(%{id: sentant_id}, %{
           event: event,
           parameters: parameters,
           passthrough: passthrough
         }) do
      {:ok, _pid} ->
        public_info = get_public_sentant_by_id(sentant_id)
        response = %{data: %{sentantSend: public_info}}
        send_json_response(conn, 200, response)
        record_request(true)

      {:error, reason} ->
        response = %{errors: [%{message: "Failed to send event: #{inspect(reason)}"}]}
        send_json_response(conn, 400, response)
        record_request(false)
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Get PUBLIC information about a specific Sentant (name, events, signals ONLY)
  defp get_public_sentant_by_id(sentant_id) do
    case Reality2.Sentants.read(%{id: sentant_id}, :definition) do
      {:ok, definition} ->
        %{
          id: sentant_id,
          name: extract_name(definition, sentant_id),
          events: extract_event_names(definition),
          signals: extract_signal_names(definition)
        }

      {:error, _} ->
        nil
    end
  end

  # Get PUBLIC information about all local Sentants (name, events, signals ONLY)
  # NO PRIVATE DATA: state, parameters, full definitions, user data
  defp get_public_sentant_info do
    case Reality2.Metadata.all(:SentantIDs) do
      sentant_map when is_map(sentant_map) ->
        sentant_map
        |> Enum.map(fn {name, id} ->
          case Reality2.Sentants.read(%{id: id}, :definition) do
            {:ok, definition} ->
              %{
                id: id,
                name: name,
                events: extract_event_names(definition),   # Event names ONLY
                signals: extract_signal_names(definition)  # Signal names ONLY
              }

            {:error, _} ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  # Extract event NAMES only (not parameters, not descriptions)
  defp extract_event_names(definition) when is_map(definition) do
    definition
    |> Map.get("events", [])
    |> Enum.map(fn
      %{"name" => name} -> name
      %{"event" => name} -> name
      event when is_binary(event) -> event
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_event_names(_), do: []

  # Extract signal NAMES only (not parameters, not descriptions)
  defp extract_signal_names(definition) when is_map(definition) do
    definition
    |> Map.get("signals", [])
    |> Enum.map(fn
      %{"name" => name} -> name
      %{"signal" => name} -> name
      signal when is_binary(signal) -> signal
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_signal_names(_), do: []

  # Extract name from definition or fall back to sentant_id
  defp extract_name(definition, sentant_id) when is_map(definition) do
    Map.get(definition, "name", sentant_id)
  end

  defp extract_name(_definition, sentant_id), do: sentant_id

  # Check if WiFi is available
  defp wifi_available? do
    case AiReality2Transnet.Wifi.list_adapters() do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  # Get mesh network info
  defp get_mesh_info do
    case AiReality2Transnet.Wifi.list_adapters() do
      {:ok, adapters} ->
        # Look for mesh interface
        mesh_adapter = Enum.find(adapters, fn adapter ->
          Map.get(adapter, :mesh_interface) != nil
        end)

        if mesh_adapter do
          # Get IPv6 link-local address
          case AiReality2Transnet.Wifi.get_ipv6_link_local(mesh_adapter.mesh_interface) do
            {:ok, ipv6} ->
              %{
                active: true,
                mesh_id: "R2MESH",
                interface: mesh_adapter.mesh_interface,
                ipv6_link_local: ipv6
              }

            {:error, _} ->
              %{
                active: true,
                mesh_id: "R2MESH",
                interface: mesh_adapter.mesh_interface,
                ipv6_link_local: nil
              }
          end
        else
          %{active: false}
        end

      {:error, _} ->
        %{active: false}
    end
  end

  # Send JSON response
  defp send_json_response(conn, status, data) do
    {:ok, json} = Jason.encode(data)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, json)
  end

  # Record request stats
  defp record_request(success) do
    GenServer.cast(AiReality2Transnet.WifiServer, {:record_request, success})
  end
end
