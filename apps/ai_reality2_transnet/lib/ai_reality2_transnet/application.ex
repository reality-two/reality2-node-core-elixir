defmodule AiReality2Transnet.Application do
  # *******************************************************************************************************************************************
  @moduledoc """
  Main supervisor for Transient Networking App.

  ## Supervision Tree

  ```
  AiReality2Transnet.Application (one_for_one)
  ├── Main                        - Plugin interface
  ├── PeerManager                 - Shared peer state (critical, isolated)
  ├── MeshRouter                  - Transport-agnostic message routing
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
        id: AiReality2Transnet.Main,
        start: {AiReality2Transnet.Main, :start_link, [AiReality2Transnet.Main]},
        restart: :transient
      },

      # PeerManager - shared peer state, critical for mesh operation
      # At top level for fault isolation - used by both discovery and connection layers
      %{
        id: AiReality2Transnet.PeerManager,
        start: {AiReality2Transnet.PeerManager, :start_link, [[]]},
        restart: :permanent
      },

      # MeshRouter - transport-agnostic message routing
      # Routes messages through available transports (BLE, WiFi, LoRa)
      %{
        id: AiReality2Transnet.MeshRouter,
        start: {AiReality2Transnet.MeshRouter, :start_link, [[]]},
        restart: :permanent
      },

      # Connection layer supervisor (Manager + Assessor) - MUST start before Discovery
      # Uses rest_for_one: if Manager restarts, Assessor also restarts
      # Discovery layer depends on ConnectionManager for hosting config
      {AiReality2Transnet.ConnectionSupervisor, []},

      # Discovery layer supervisor (BLE + LoRa)
      # Fault-isolated: discovery failures don't affect connection management
      # Starts AFTER ConnectionSupervisor because Bluetooth needs ConnectionManager
      {AiReality2Transnet.DiscoverySupervisor, []},

      # R2Mesh - mesh networking logic
      # Independent of discovery/connection specifics
      %{
        id: AiReality2Transnet.R2Mesh,
        start: {AiReality2Transnet.R2Mesh, :start_link, [[]]},
        restart: :permanent
      }
    ]

    node_name = Reality2.Bootstrap.get(:node_name, "unknown")
    Logger.info("[ai.reality2.transnet:#{node_name}] started with hierarchical supervision")
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  @doc """
  Returns a map describing the current supervision tree structure.

  Useful for debugging and monitoring.

  ## Example

      AiReality2Transnet.Application.supervision_tree()
      # => %{
      #   name: AiReality2Transnet.Application,
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

      AiReality2Transnet.Application.print_supervision_tree()
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
