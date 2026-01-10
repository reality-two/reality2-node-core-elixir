defmodule AiReality2Transnet.ConnectionAssessor do
  @moduledoc """
  Continuously assesses WiFi hotspot connections and triggers handovers.

  Implements the connection quality assessment and handover decision logic
  for Reality2's mobile hotspot architecture.

  ## Assessment Criteria

  Scores potential host nodes based on:
  - **RSSI** (signal strength): -45 dBm = excellent, -80 dBm = poor
  - **Fixed anchor bonus**: POS/fixed nodes get preference (sticky)
  - **Hotspot availability**: Only nodes currently hosting count
  - **Client load**: Fewer connected clients = higher score

  ## Hysteresis Logic

  Prevents thrashing by requiring:
  - **Score margin (Δ)**: New host must score significantly better (default: +10 points)
  - **Dwell time**: Must stay on current host for minimum duration (default: 30s)
  - **Signal threshold**: Current host must be degraded (< -75 dBm) OR new is much better

  ## Usage

  ```elixir
  # Start assessor (runs automatically)
  ConnectionAssessor.start_link([])

  # Force assessment
  ConnectionAssessor.assess_now()

  # Get current best candidate
  {:ok, best} = ConnectionAssessor.get_best_candidate()
  # => %{peer_id: "...", score: 85, reason: "better_signal"}

  # Check if should handover
  case ConnectionAssessor.should_handover?() do
    {:yes, candidate, _reason} ->
      ConnectionManager.handover_to(candidate.peer_id, candidate.join_offer)
    {:no, _reason} ->
      Logger.debug("Staying on current host")
  end
  ```

  ## Scoring Formula

  ```
  base_score = 100 - abs(rssi)              # -45 dBm → 55 points
  + (is_fixed_anchor? ? 20 : 0)             # Fixed bonus
  + (hosting? ? 10 : 0)                     # Actually hosting
  - (client_count * 2)                      # Penalty for load
  + (upstream_quality / 10)                 # Upstream quality bonus
  ```

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  alias AiReality2Transnet.{PeerManager, ConnectionManager}

  # Configuration
  # Check every 15 seconds
  @assessment_interval_ms 15_000
  # New host must score +10 better
  @handover_score_margin 10
  # Stay connected for at least 30s
  @min_dwell_time_ms 30_000
  # Current signal worse than this triggers handover
  @degraded_signal_threshold -75
  # Average last 5 RSSI readings
  @rssi_averaging_window 5

  @type candidate :: %{
          peer_id: String.t(),
          score: integer(),
          rssi: integer(),
          rssi_avg: float(),
          is_fixed_anchor: boolean(),
          hosting: boolean(),
          client_count: integer(),
          upstream_quality: integer(),
          join_offer: map() | nil,
          last_updated: integer()
        }

  @type assessment_result ::
          {:yes, candidate(), String.t()}
          | {:no, String.t()}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Forces an immediate assessment (doesn't wait for next interval).

  Returns current best candidate if any.
  """
  @spec assess_now() :: {:ok, candidate()} | {:error, :no_candidates}
  def assess_now do
    GenServer.call(__MODULE__, :assess_now)
  end

  @doc """
  Gets the current best candidate without triggering assessment.
  """
  @spec get_best_candidate() :: {:ok, candidate()} | {:error, :no_candidates}
  def get_best_candidate do
    GenServer.call(__MODULE__, :get_best_candidate)
  end

  @doc """
  Checks if a handover should be performed now.

  Returns:
  - `{:yes, candidate, reason}` - Should handover to this candidate
  - `{:no, reason}` - Stay on current host
  """
  @spec should_handover?() :: assessment_result()
  def should_handover? do
    GenServer.call(__MODULE__, :should_handover)
  end

  @doc """
  Gets current assessment statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets the full internal state of the assessor.

  Useful for debugging and monitoring.
  """
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Start assessment timer (runs every @assessment_interval_ms)
    schedule_assessment()

    state = %{
      # All scored candidates: %{peer_id => candidate_struct}
      candidates: %{},

      # RSSI smoothing: %{peer_id => [rssi1, rssi2, ...]} (last @rssi_averaging_window values)
      # Prevents handover thrashing due to momentary signal fluctuations
      rssi_history: %{},

      # Current highest-scoring candidate (may not trigger handover due to hysteresis)
      best_candidate: nil,

      # Statistics for monitoring and debugging
      stats: %{
        assessments_performed: 0,
        handovers_recommended: 0,
        candidates_evaluated: 0
      }
    }

    Logger.info(
      "[ConnectionAssessor] Started - assessment interval: #{@assessment_interval_ms}ms"
    )

    {:ok, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call(:assess_now, _from, state) do
    new_state = perform_assessment(state)

    case new_state.best_candidate do
      nil -> {:reply, {:error, :no_candidates}, new_state}
      candidate -> {:reply, {:ok, candidate}, new_state}
    end
  end

  @impl true
  def handle_call(:get_best_candidate, _from, state) do
    case state.best_candidate do
      nil -> {:reply, {:error, :no_candidates}, state}
      candidate -> {:reply, {:ok, candidate}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:should_handover, _from, state) do
    result = evaluate_handover_decision(state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        candidate_count: map_size(state.candidates),
        best_candidate_score: if(state.best_candidate, do: state.best_candidate.score, else: nil)
      })

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:assess, state) do
    # Periodic assessment cycle (triggered every @assessment_interval_ms)
    # Evaluates all discovered peers and decides whether to handover

    # Step 1: Score all peer candidates based on RSSI, capabilities, load, etc.
    new_state = perform_assessment(state)

    # Step 2: Apply hysteresis logic to decide if handover is warranted
    # Only handover if new candidate is significantly better (prevents ping-pong)
    case evaluate_handover_decision(new_state) do
      {:yes, candidate, reason} ->
        Logger.info(
          "[ConnectionAssessor] Handover recommended: #{String.slice(candidate.peer_id, 0..7)} (#{reason})"
        )

        # Trigger handover via ConnectionManager
        case candidate.join_offer do
          nil ->
            # No join offer cached - can't handover yet
            # This will be resolved on next assessment after GATT read
            Logger.warning("[ConnectionAssessor] No join offer available for candidate")

          join_offer ->
            Logger.info("[ConnectionAssessor] Initiating handover...")

            # Run handover in background task to avoid blocking assessor
            # Assessor continues monitoring during handover
            Task.start(fn ->
              ConnectionManager.handover_to(candidate.peer_id, join_offer)
            end)
        end

        final_state = %{
          new_state
          | stats: Map.update!(new_state.stats, :handovers_recommended, &(&1 + 1))
        }

        schedule_assessment()
        {:noreply, final_state}

      {:no, reason} ->
        # Current connection is still optimal, OR no candidates available
        Logger.debug("[ConnectionAssessor] No handover needed: #{reason}")

        # Check if we should yield hosting to a better candidate
        maybe_yield_hosting()

        # Check if we should start hosting (no one else is hosting and we're idle)
        maybe_start_hosting(new_state, reason)

        schedule_assessment()
        {:noreply, new_state}
    end
  end

  # If we're currently hosting, check if we should yield to a better host candidate
  #
  # Now uses peer priorities from BLE beacons for informed yield decisions:
  # - If a peer has HIGHER priority than us, yield immediately
  # - If peers have EQUAL priority, yield to lower node_id
  # - If we have the HIGHEST priority, never yield
  defp maybe_yield_hosting do
    case ConnectionManager.get_connection_status() do
      {:ok, %{state: :hosting_ap}} ->
        my_priority = AiReality2Transnet.Wifi.get_hosting_priority()
        my_node_id = Reality2.Bootstrap.get(:node_id)
        peers = PeerManager.get_all_peers()

        if map_size(peers) > 0 do
          # Get the highest priority among peers (from BLE beacon data)
          max_peer_priority = PeerManager.get_max_peer_priority()

          cond do
            # A peer has higher priority - yield to them
            max_peer_priority > my_priority ->
              # Find the peer with highest priority (and lowest ID if tied)
              best_peer = peers
                |> Enum.filter(fn {_id, peer} -> Map.get(peer, :hosting_priority, 0) == max_peer_priority end)
                |> Enum.min_by(fn {id, _peer} -> id end)

              {best_id, best_peer_info} = best_peer
              best_name = Map.get(best_peer_info, :node_name, String.slice(best_id, 0..7))
              Logger.info("[ConnectionAssessor] Yielding hosting to #{best_name} (priority #{max_peer_priority} > our #{my_priority})")
              yield_hosting()

            # Equal priority - use node_id as tie-breaker
            max_peer_priority == my_priority && my_priority < 100 ->
              peers_with_equal = peers
                |> Enum.filter(fn {_id, peer} -> Map.get(peer, :hosting_priority, 0) == my_priority end)
                |> Enum.map(fn {id, _peer} -> id end)

              all_candidates = [my_node_id | peers_with_equal]
              lowest_id = Enum.min(all_candidates)

              if lowest_id != my_node_id do
                Logger.info("[ConnectionAssessor] Yielding hosting to #{String.slice(lowest_id, 0..7)}... (same priority #{my_priority}, lower ID)")
                yield_hosting()
              end

            # We have higher priority than all peers, or priority 100 - keep hosting
            true ->
              :ok
          end
        end

      _ ->
        :ok
    end
  end

  defp yield_hosting do
    Task.start(fn ->
      case ConnectionManager.stop_hosting() do
        :ok ->
          Logger.info("[ConnectionAssessor] Stopped hosting - waiting for better host to start...")
          # Give the other node time to start hosting
          Process.sleep(5_000)

        {:error, reason} ->
          Logger.warning("[ConnectionAssessor] Failed to stop hosting: #{inspect(reason)}")
      end
    end)
  end

  # If no candidates are available and we're not connected, consider becoming a host
  defp maybe_start_hosting(_state, reason) do
    # Only consider starting if:
    # 1. No viable candidates (no one is hosting)
    # 2. We're not already connected or hosting
    # 3. We have WiFi capability
    # 4. There are discovered peers who could connect to us
    # 5. We "win" the selection (best hosting priority, then lowest node_id as tie-breaker)

    if reason in ["no_candidates_available", "no_better_candidate", "no_join_offer_available", "no_join_offer_for_candidate"] do
      case ConnectionManager.get_connection_status() do
        {:ok, %{state: :disconnected, hosting: hosting}} when hosting != true ->
          # We're disconnected and not hosting - check if we should start
          peers = PeerManager.get_all_peers()
          Logger.debug("[ConnectionAssessor] Checking hosting: #{map_size(peers)} peers discovered")

          if map_size(peers) > 0 do
            # Check our hosting priority (internet + NAT capability)
            my_priority = AiReality2Transnet.Wifi.get_hosting_priority()
            my_node_id = Reality2.Bootstrap.get(:node_id)

            # Determine if we should host based on priority and node_id
            should_host = should_we_host?(my_priority, my_node_id, peers)

            if should_host do
              # We should be the host
              case AiReality2Transnet.Wifi.list_adapters() do
                {:ok, [_ | _]} ->
                  reason_text = cond do
                    my_priority >= 100 -> "wired internet + NAT capability (best host)"
                    my_priority >= 75 -> "NAT capability (may lose internet)"
                    my_priority >= 50 -> "internet access (single interface)"
                    true -> "lowest ID (no internet)"
                  end

                  Logger.info("[ConnectionAssessor] Starting hotspot - #{reason_text} (priority: #{my_priority})")

                  Task.start(fn ->
                    case ConnectionManager.start_hosting() do
                      {:ok, config} ->
                        Logger.info("[ConnectionAssessor] Now hosting: #{config.ssid}")

                      {:error, err} ->
                        Logger.warning("[ConnectionAssessor] Failed to start hosting: #{inspect(err)}")
                    end
                  end)

                _ ->
                  Logger.debug("[ConnectionAssessor] No WiFi adapter available for hosting")
              end
            else
              # We should be a client - try to find and connect to an R2 hotspot
              Logger.info("[ConnectionAssessor] Another node should host - scanning for R2 hotspots...")

              Task.start(fn ->
                try_connect_to_r2_hotspot()
              end)
            end
          end

        {:ok, %{state: conn_state}} ->
          Logger.debug("[ConnectionAssessor] Not starting host - current state: #{conn_state}")

        _ ->
          :ok
      end
    end
  end

  # Determine if we should be the host based on priority comparison with peers
  # Priority scoring:
  # - 100: Wired internet + WiFi (can NAT, keeps internet) - BEST
  # - 75: Can NAT but WiFi-only internet (will lose internet as host)
  # - 50: Has internet but single interface
  # - 10: No internet but has WiFi
  # - 0: No WiFi capability
  #
  # Now uses peer priorities from BLE beacons for informed decisions!
  defp should_we_host?(my_priority, my_node_id, peers) do
    # Get the highest priority among peers (from BLE beacon data)
    max_peer_priority = PeerManager.get_max_peer_priority()

    Logger.debug("[ConnectionAssessor] Host selection: my_priority=#{my_priority}, max_peer_priority=#{max_peer_priority}")

    cond do
      # We have the best possible priority (wired internet + NAT)
      # Always become host regardless of peers
      my_priority >= 100 ->
        Logger.debug("[ConnectionAssessor] High priority (#{my_priority}) - wired internet, becoming host")
        true

      # We have higher priority than all peers - become host
      my_priority > max_peer_priority ->
        Logger.debug("[ConnectionAssessor] Higher priority than peers (#{my_priority} > #{max_peer_priority}) - becoming host")
        true

      # We have equal priority to highest peer - use node_id as tie-breaker
      my_priority == max_peer_priority ->
        # Find peer(s) with max priority
        peers_with_max = peers
          |> Enum.filter(fn {_id, peer} -> Map.get(peer, :hosting_priority, 0) == max_peer_priority end)
          |> Enum.map(fn {id, _peer} -> id end)

        all_candidates = [my_node_id | peers_with_max]
        lowest_id = Enum.min(all_candidates)

        if my_node_id == lowest_id do
          Logger.debug("[ConnectionAssessor] Equal priority (#{my_priority}), lowest ID - becoming host")
          true
        else
          Logger.debug("[ConnectionAssessor] Equal priority but node #{String.slice(lowest_id, 0..7)}... has lower ID")
          false
        end

      # A peer has higher priority - let them host
      true ->
        Logger.debug("[ConnectionAssessor] Peer has higher priority (#{max_peer_priority} > #{my_priority}) - waiting for them to host")
        false
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Assessment Logic
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp perform_assessment(state) do
    Logger.debug("[ConnectionAssessor] Performing assessment...")

    # Get all discovered peers
    peers = PeerManager.get_all_peers()

    # Score each peer
    {candidates, rssi_history} =
      Enum.reduce(peers, {%{}, state.rssi_history}, fn {peer_id, peer},
                                                       {acc_candidates, acc_rssi} ->
        # Update RSSI history
        new_rssi_history = update_rssi_history(acc_rssi, peer_id, peer.rssi)

        # Calculate score
        case score_candidate(peer, new_rssi_history[peer_id]) do
          {:ok, candidate} ->
            {Map.put(acc_candidates, peer_id, candidate), new_rssi_history}

          {:skip, _reason} ->
            {acc_candidates, new_rssi_history}
        end
      end)

    # Find best candidate
    best =
      candidates
      |> Map.values()
      |> Enum.max_by(fn c -> c.score end, fn -> nil end)

    new_state = %{
      state
      | candidates: candidates,
        rssi_history: rssi_history,
        best_candidate: best,
        stats: %{
          state.stats
          | assessments_performed: state.stats.assessments_performed + 1,
            candidates_evaluated: map_size(candidates)
        }
    }

    if best do
      Logger.debug(
        "[ConnectionAssessor] Best candidate: #{String.slice(best.peer_id, 0..7)} (score: #{best.score})"
      )
    else
      Logger.debug("[ConnectionAssessor] No viable candidates")
    end

    new_state
  end

  defp score_candidate(peer, rssi_history) do
    # Score a peer based on multiple factors to determine suitability as host
    # Returns {:ok, candidate} or {:skip, reason}

    # Skip peers without RSSI data (not visible or too far away)
    if peer.rssi == nil do
      {:skip, "no_rssi"}
    else
      # Extract capabilities advertised in BLE beacon
      capabilities = peer.capabilities || %{}
      hosting = Map.get(capabilities, :can_host_ap, false)
      is_fixed = Map.get(capabilities, :is_fixed_anchor, false)
      client_count = Map.get(capabilities, :client_count, 0)
      upstream_quality = Map.get(capabilities, :upstream_quality, 50)

      # Only consider peers that are actively hosting a hotspot
      # Peers that can host but aren't currently don't count
      if not hosting do
        {:skip, "not_hosting"}
      else
        # Calculate smoothed RSSI (average of last @rssi_averaging_window readings)
        # This prevents handover triggered by momentary signal dips
        rssi_avg = calculate_average_rssi(rssi_history)

        # Base score from signal strength (higher is better)
        # Examples:
        #   -45 dBm (excellent) → 100 - 45 = 55 points
        #   -60 dBm (good)      → 100 - 60 = 40 points
        #   -75 dBm (poor)      → 100 - 75 = 25 points
        base_score = 100 - abs(round(rssi_avg))

        # Apply bonuses and penalties:
        # Prefer fixed anchors (sticky)
        fixed_bonus = if is_fixed, do: 20, else: 0
        # Bonus for being active
        hosting_bonus = 10
        # Prefer less-loaded hosts
        load_penalty = client_count * 2
        # Factor in upstream quality (0-100 → 0-10)
        upstream_bonus = div(upstream_quality, 10)

        final_score = base_score + fixed_bonus + hosting_bonus - load_penalty + upstream_bonus

        # Attempt to retrieve cached join offer from GATT
        # May be nil if GATT read hasn't happened yet
        join_offer = get_join_offer_for_peer(peer)

        candidate = %{
          peer_id: peer.node_id,
          score: final_score,
          rssi: peer.rssi,
          rssi_avg: rssi_avg,
          is_fixed_anchor: is_fixed,
          hosting: hosting,
          client_count: client_count,
          upstream_quality: upstream_quality,
          join_offer: join_offer,
          last_updated: System.system_time(:millisecond)
        }

        {:ok, candidate}
      end
    end
  end

  defp update_rssi_history(rssi_history, peer_id, new_rssi) when is_integer(new_rssi) do
    history = Map.get(rssi_history, peer_id, [])
    updated_history = [new_rssi | history] |> Enum.take(@rssi_averaging_window)
    Map.put(rssi_history, peer_id, updated_history)
  end

  defp update_rssi_history(rssi_history, _peer_id, nil), do: rssi_history

  defp calculate_average_rssi(rssi_list) when is_list(rssi_list) and length(rssi_list) > 0 do
    Enum.sum(rssi_list) / length(rssi_list)
  end

  defp calculate_average_rssi(_), do: -80.0

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Handover Decision Logic
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp evaluate_handover_decision(state) do
    # Get current connection status
    case ConnectionManager.get_connection_status() do
      {:ok, status} when status.state == :connected_as_client ->
        evaluate_handover_for_connected(status, state)

      {:ok, status} when status.state == :disconnected ->
        # Not connected - recommend best candidate if available
        case state.best_candidate do
          nil ->
            {:no, "no_candidates_available"}

          candidate ->
            if candidate.join_offer do
              {:yes, candidate, "initial_connection"}
            else
              {:no, "no_join_offer_available"}
            end
        end

      {:ok, status} when status.state == :hosting_ap ->
        # We're hosting - no need to connect anywhere
        {:no, "currently_hosting"}

      {:ok, status} when status.state in [:connecting, :handover_in_progress] ->
        # Connection/handover in progress - wait for it to complete
        {:no, "connection_in_progress"}

      _ ->
        {:no, "invalid_connection_state"}
    end
  end

  defp evaluate_handover_for_connected(status, state) do
    # Hysteresis logic: only handover if new candidate is significantly better
    # This prevents "ping-pong" behavior where node bounces between similar hosts

    best = state.best_candidate

    cond do
      # No alternative candidates available
      best == nil ->
        {:no, "no_alternative_candidates"}

      # Already connected to the best candidate
      best.peer_id == status.host_peer_id ->
        {:no, "already_on_best_host"}

      # Join offer not yet cached from GATT (wait for next assessment)
      best.join_offer == nil ->
        {:no, "no_join_offer_for_candidate"}

      # Dwell time requirement: stay on current host for minimum duration
      # Prevents rapid handovers (default: 30 seconds)
      not sufficient_dwell_time?(status) ->
        {:no, "min_dwell_time_not_met"}

      # Current signal is degraded (< -75 dBm): immediate handover allowed
      # This is the "emergency exit" - don't wait for better scores
      current_signal_degraded?(status) ->
        {:yes, best, "current_signal_degraded"}

      # Score margin requirement: new host must score +10 points better
      # This is the core hysteresis mechanism
      sufficient_score_margin?(best, status, state) ->
        {:yes, best, "better_candidate_found"}

      # New candidate exists but doesn't meet hysteresis threshold
      true ->
        {:no, "hysteresis_threshold_not_met"}
    end
  end

  defp sufficient_dwell_time?(status) do
    if status.connected_at do
      now = System.system_time(:millisecond)
      time_connected = now - status.connected_at
      time_connected >= @min_dwell_time_ms
    else
      false
    end
  end

  defp current_signal_degraded?(status) do
    if status.signal_strength do
      status.signal_strength < @degraded_signal_threshold
    else
      # If no signal data, assume not degraded
      false
    end
  end

  defp sufficient_score_margin?(candidate, status, state) do
    # Get current host score
    current_host = Map.get(state.candidates, status.host_peer_id)

    case current_host do
      nil ->
        # Don't know current host score, use conservative approach
        # Absolute threshold
        candidate.score >= 70

      current ->
        # Require margin over current
        candidate.score >= current.score + @handover_score_margin
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Join Offer Retrieval
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_join_offer_for_peer(peer) do
    # For now, we'll need to construct join offer from peer capabilities
    # In practice, this would be cached from last GATT read
    # TODO: Implement GATT caching in PeerManager

    # Placeholder: construct expected join offer
    case peer.capabilities do
      %{can_host_ap: true} = _caps ->
        # We need actual credentials from GATT
        # For now, return nil and let GATT exchange happen during handover
        nil

      _ ->
        nil
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - R2 Hotspot Discovery and Connection
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp try_connect_to_r2_hotspot do
    # Try to find and connect to an R2 hotspot
    # This runs when we determine another node should be hosting

    case AiReality2Transnet.Wifi.list_adapters() do
      {:ok, [adapter | _]} when is_map(adapter) ->
        interface = adapter.interface
        Logger.info("[ConnectionAssessor] Scanning for R2 hotspots on #{interface}...")

        case AiReality2Transnet.Wifi.find_r2_hotspots(interface) do
          {:ok, []} ->
            Logger.info("[ConnectionAssessor] No R2 hotspots found yet - will retry on next assessment")

          {:ok, hotspots} ->
            Logger.info("[ConnectionAssessor] Found #{length(hotspots)} R2 hotspot(s)")

            # Try to connect to the first (strongest signal) R2 hotspot
            [best | _] = hotspots
            Logger.info("[ConnectionAssessor] Attempting to connect to #{best.ssid} (signal: #{best.signal})")

            case AiReality2Transnet.Wifi.connect_to_network(interface, best.ssid, best.psk) do
              {:ok, _uuid} ->
                Logger.info("[ConnectionAssessor] Successfully connected to #{best.ssid}!")

                # Update connection state
                ConnectionManager.report_wifi_connected(best.ssid)

              {:error, reason} ->
                Logger.warning("[ConnectionAssessor] Failed to connect to #{best.ssid}: #{reason}")
            end

          {:error, reason} ->
            Logger.warning("[ConnectionAssessor] Failed to scan for R2 hotspots: #{reason}")
        end

      _ ->
        Logger.debug("[ConnectionAssessor] No WiFi adapter available for client connection")
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Scheduling
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp schedule_assessment do
    Process.send_after(self(), :assess, @assessment_interval_ms)
  end
end
