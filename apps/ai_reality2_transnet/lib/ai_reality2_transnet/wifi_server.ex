defmodule AiReality2Transnet.WifiServer do
  # *******************************************************************************************************************************************
  @moduledoc """
  WiFi mesh networking server for Transient Networks. Handles WiFi adapter discovery,
  mesh interface creation, and peer management.

  ## WiFi Operations:
  - list_adapters - Get all WiFi adapters on the system
  - create_mesh - Create and start a mesh interface
  - list_peers - List connected mesh peers
  - get_ipv6 - Get IPv6 link-local address for interface

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  # *******************************************************************************************************************************************

  alias Reality2.Sentants, as: Sentants
  alias Reality2.Helpers.R2Map, as: R2Map
  alias AiReality2Transnet.Wifi
  use GenServer, restart: :transient
  require Logger

  @default_mesh_id "REALITY2_MESH"
  @default_frequency 2437  # Channel 6

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Gets the current WiFi server state and statistics.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(state) do
    initial_state = %{
      mesh_interfaces: %{},
      peers: %{},
      adapters: [],
      commands_processed: 0
    }

    {:ok, Map.merge(state, initial_state)}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Terminating WiFi service")

    # Clean up mesh interfaces
    Enum.each(state.mesh_interfaces, fn {mesh_interface, _} ->
      Wifi.destroy_mesh_interface(mesh_interface)
    end)

    :ok
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_call
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # handle_cast - Command Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_cast(%{command: "list_adapters"}, state) do
    list_adapters(state)
  end

  def handle_cast(%{command: "create_mesh", parameters: parameters}, state) do
    create_mesh(state, parameters)
  end

  def handle_cast(%{command: "destroy_mesh", parameters: parameters}, state) do
    destroy_mesh(state, parameters)
  end

  def handle_cast(%{command: "list_peers", parameters: parameters}, state) do
    list_peers(state, parameters)
  end

  def handle_cast(%{command: "get_ipv6", parameters: parameters}, state) do
    get_ipv6(state, parameters)
  end

  def handle_cast(_, state), do: {:noreply, state}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Helper Functions - Command Implementations
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp list_adapters(state) do
    case Wifi.list_adapters() do
      {:ok, adapters} ->
        Logger.info("Found #{length(adapters)} WiFi adapter(s)")

        # Send result to all Sentants
        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_adapters",
            adapters: adapters
          }
        })

        new_state = %{
          state |
          adapters: adapters,
          commands_processed: state.commands_processed + 1
        }
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to list WiFi adapters: #{reason}")

        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_error",
            error: "list_adapters_failed",
            reason: reason
          }
        })

        {:noreply, state}
    end
  end

  defp create_mesh(state, parameters) do
    interface = R2Map.get(parameters, :interface, "wlan0")
    mesh_interface = R2Map.get(parameters, :mesh_interface, "mesh0")
    mesh_id = R2Map.get(parameters, :mesh_id, @default_mesh_id)
    frequency = R2Map.get(parameters, :frequency, @default_frequency)

    Logger.info("Creating mesh interface #{mesh_interface} on #{interface}")

    with :ok <- Wifi.create_mesh_interface(interface, mesh_interface),
         :ok <- Wifi.start_mesh(mesh_interface, mesh_id, frequency) do

      Logger.info("Mesh interface #{mesh_interface} created and started")

      # Get IPv6 address
      ipv6_result = Wifi.get_ipv6_link_local(mesh_interface)
      ipv6 = case ipv6_result do
        {:ok, addr} -> addr
        _ -> nil
      end

      mesh_info = %{
        interface: interface,
        mesh_interface: mesh_interface,
        mesh_id: mesh_id,
        frequency: frequency,
        ipv6_address: ipv6,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      # Notify Sentants
      Sentants.sendto_all(%{
        event: "__internal",
        parameters: %{
          activity: "wifi_mesh_created",
          mesh: mesh_info
        }
      })

      new_state = %{
        state |
        mesh_interfaces: Map.put(state.mesh_interfaces, mesh_interface, mesh_info),
        commands_processed: state.commands_processed + 1
      }
      {:noreply, new_state}

    else
      {:error, reason} ->
        Logger.error("Failed to create mesh: #{reason}")

        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_error",
            error: "create_mesh_failed",
            reason: reason
          }
        })

        {:noreply, state}
    end
  end

  defp destroy_mesh(state, parameters) do
    mesh_interface = R2Map.get(parameters, :mesh_interface, "mesh0")

    case Wifi.destroy_mesh_interface(mesh_interface) do
      :ok ->
        Logger.info("Destroyed mesh interface #{mesh_interface}")

        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_mesh_destroyed",
            mesh_interface: mesh_interface
          }
        })

        new_state = %{
          state |
          mesh_interfaces: Map.delete(state.mesh_interfaces, mesh_interface),
          commands_processed: state.commands_processed + 1
        }
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to destroy mesh: #{reason}")

        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_error",
            error: "destroy_mesh_failed",
            reason: reason
          }
        })

        {:noreply, state}
    end
  end

  defp list_peers(state, parameters) do
    mesh_interface = R2Map.get(parameters, :mesh_interface, "mesh0")

    case Wifi.list_mesh_peers(mesh_interface) do
      {:ok, peers} ->
        Logger.info("Found #{length(peers)} mesh peer(s) on #{mesh_interface}")

        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_peers",
            mesh_interface: mesh_interface,
            peers: peers,
            count: length(peers)
          }
        })

        new_state = %{
          state |
          peers: Map.put(state.peers, mesh_interface, peers),
          commands_processed: state.commands_processed + 1
        }
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to list peers: #{reason}")

        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_error",
            error: "list_peers_failed",
            reason: reason
          }
        })

        {:noreply, state}
    end
  end

  defp get_ipv6(state, parameters) do
    interface = R2Map.get(parameters, :interface, "mesh0")

    case Wifi.get_ipv6_link_local(interface) do
      {:ok, address} ->
        Logger.info("IPv6 address for #{interface}: #{address}")

        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_ipv6",
            interface: interface,
            ipv6_address: address
          }
        })

        new_state = %{state | commands_processed: state.commands_processed + 1}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to get IPv6: #{reason}")

        Sentants.sendto_all(%{
          event: "__internal",
          parameters: %{
            activity: "wifi_error",
            error: "get_ipv6_failed",
            reason: reason
          }
        })

        {:noreply, state}
    end
  end
end
