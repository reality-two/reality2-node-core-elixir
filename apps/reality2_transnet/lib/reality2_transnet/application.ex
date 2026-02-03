defmodule Reality2Transnet.Application do
  # *******************************************************************************************************************************************
  @moduledoc """
  Main supervisor for Transient Networking App.

  ## Supervision Tree

  ```
  Reality2Transnet.Application (one_for_one)
  ├── Main                        - Plugin interface
  ├── JoinRequests                - Ephemeral storage for pending join requests
  ├── HiveMembers                 - Persistent storage for approved members
  ├── HiveIdentity                - Cryptographic Hive identity (Ed25519)
  ├── HiveDirectory               - Distributed eventually-consistent hive directory
  ├── PeerManager                 - Shared peer state (critical, isolated)
  ├── MeshRouter                  - Transport-agnostic message routing
  ├── CloudConnector              - Persistent connections to cloud hive nodes
  ├── ConnectionSupervisor        - Data layer (rest_for_one) [STARTS FIRST]
  │   ├── ConnectionManager       - WiFi hotspot/client management
  │   └── ConnectionAssessor      - Quality assessment (depends on Manager)
  ├── DiscoverySupervisor         - Discovery layer (fault-isolated)
  │   ├── Bluetooth               - BLE beacon discovery (CORE, needs ConnMgr)
  │   └── LoRaMesh                - LoRa mesh networking
  └── R2Mesh                      - Legacy mesh (being replaced by MeshRouter)
  ```

  ## Transport Hierarchy

  BLE beacons are the CORE discovery mechanism. WiFi and LoRa are data
  transports that activate after BLE discovery identifies nearby peers.
  ```

  ## Design Rationale

  1. **PeerManager at top level**: Shared state used by both discovery and
     connection layers. Isolated so a crash doesn't cascade.

  2. **DiscoverySupervisor (one_for_one)**: BLE and LoRa can fail independently.
     Optional hardware - uses :transient restart.

  3. **ConnectionSupervisor (rest_for_one)**: If ConnectionManager restarts,
     ConnectionAssessor must also restart because it depends on Manager state.

  4. **Main and R2Mesh**: Independent components that don't need sub-supervisors.

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Main plugin interface - transient (normal exit is OK)
      %{
        id: Reality2Transnet.Main,
        start: {Reality2Transnet.Main, :start_link, [Reality2Transnet.Main]},
        restart: :transient
      },

      # JoinRequests - ephemeral storage for pending hive join requests
      %{
        id: Reality2Transnet.JoinRequests,
        start: {Reality2Transnet.JoinRequests, :start_link, [[]]},
        restart: :permanent
      },

      # HiveMembers - persistent storage for approved hive members
      %{
        id: Reality2Transnet.HiveMembers,
        start: {Reality2Transnet.HiveMembers, :start_link, [[]]},
        restart: :permanent
      },

      # HiveIdentity - cryptographic identity for the Hive
      # MUST start before PeerManager since peers need Hive context
      %{
        id: Reality2Transnet.HiveIdentity,
        start: {Reality2Transnet.HiveIdentity, :start_link, [[]]},
        restart: :permanent
      },

      # HiveDirectory - distributed eventually-consistent hive directory
      # MUST start after HiveIdentity (needs hive_id), before PeerManager
      %{
        id: Reality2Transnet.HiveDirectory,
        start: {Reality2Transnet.HiveDirectory, :start_link, [[]]},
        restart: :permanent
      },

      # PeerManager - shared peer state, critical for mesh operation
      # At top level for fault isolation - used by both discovery and connection layers
      %{
        id: Reality2Transnet.PeerManager,
        start: {Reality2Transnet.PeerManager, :start_link, [[]]},
        restart: :permanent
      },

      # MeshRouter - transport-agnostic message routing
      # Routes messages through available transports (BLE, WiFi, LoRa, Internet)
      %{
        id: Reality2Transnet.MeshRouter,
        start: {Reality2Transnet.MeshRouter, :start_link, [[]]},
        restart: :permanent
      },

      # CloudConnector - persistent connections to cloud-hosted hive nodes
      # Enables backup, relay, and analytics via internet (GSM, wired, WiFi-to-internet)
      # Starts after MeshRouter so it can relay messages immediately on connect
      %{
        id: Reality2Transnet.CloudConnector,
        start: {Reality2Transnet.CloudConnector, :start_link, [[]]},
        restart: :permanent
      },

      # Connection layer supervisor (Manager + Assessor) - MUST start before Discovery
      # Uses rest_for_one: if Manager restarts, Assessor also restarts
      # Discovery layer depends on ConnectionManager for hosting config
      {Reality2Transnet.ConnectionSupervisor, []},

      # Discovery layer supervisor (BLE + LoRa)
      # Fault-isolated: discovery failures don't affect connection management
      # Starts AFTER ConnectionSupervisor because Bluetooth needs ConnectionManager
      {Reality2Transnet.DiscoverySupervisor, []},

      # R2Mesh - mesh networking logic
      # Independent of discovery/connection specifics
      %{
        id: Reality2Transnet.R2Mesh,
        start: {Reality2Transnet.R2Mesh, :start_link, [[]]},
        restart: :permanent
      },

      # HiveJoinBle - joiner-side BLE GATT client for hive join requests
      %{
        id: Reality2Transnet.HiveJoinBle,
        start: {Reality2Transnet.HiveJoinBle, :start_link, [[]]},
        restart: :permanent
      }
    ]

    node_name = Reality2.Bootstrap.get(:node_name, "unknown")
    Logger.info("[reality2.transnet:#{node_name}] started with hierarchical supervision")
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  @doc """
  Returns a map describing the current supervision tree structure.

  Useful for debugging and monitoring.

  ## Example

      Reality2Transnet.Application.supervision_tree()
      # => %{
      #   name: Reality2Transnet.Application,
      #   strategy: :one_for_one,
      #   children: [...]
      # }
  """
  def supervision_tree do
    build_tree(__MODULE__)
  end

  defp build_tree(supervisor) do
    case Supervisor.which_children(supervisor) do
      children when is_list(children) ->
        %{
          name: supervisor,
          strategy: get_strategy(supervisor),
          children: Enum.map(children, fn {id, pid, type, _modules} ->
            child_info = %{
              id: id,
              pid: pid,
              type: type,
              alive: is_pid(pid) and Process.alive?(pid)
            }

            # Recursively get sub-supervisor trees
            if type == :supervisor and is_pid(pid) do
              Map.put(child_info, :children, build_tree(pid))
            else
              child_info
            end
          end)
        }

      _ ->
        %{name: supervisor, error: :not_found}
    end
  rescue
    _ -> %{name: supervisor, error: :exception}
  end

  defp get_strategy(supervisor) do
    case :sys.get_state(supervisor) do
      %{strategy: strategy} -> strategy
      {_state, %{strategy: strategy}} -> strategy
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end

  @doc """
  Prints the supervision tree in a human-readable format.

  ## Example

      Reality2Transnet.Application.print_supervision_tree()
  """
  def print_supervision_tree do
    tree = supervision_tree()
    print_tree(tree, 0)
    :ok
  end

  defp print_tree(%{name: name, strategy: strategy, children: children}, indent) do
    prefix = String.duplicate("  ", indent)
    IO.puts("#{prefix}#{inspect(name)} (#{strategy})")

    Enum.each(children, fn child ->
      status = if child.alive, do: "✓", else: "✗"

      case child[:children] do
        %{children: _} = sub_tree ->
          print_tree(sub_tree, indent + 1)

        _ ->
          IO.puts("#{prefix}  #{status} #{child.id} [#{child.type}]")
      end
    end)
  end

  defp print_tree(%{name: name, error: error}, indent) do
    prefix = String.duplicate("  ", indent)
    IO.puts("#{prefix}#{inspect(name)} (error: #{error})")
  end
end
