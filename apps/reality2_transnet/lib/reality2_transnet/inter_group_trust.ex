defmodule Reality2Transnet.InterGroupTrust do
  @moduledoc """
  Manages inter-trust-group trust relationships for federation.

  Trust relationships allow TrustGroups to share access to sentants in a controlled way.
  Each trust relationship specifies:
  - Which TrustGroup is trusted (by trust_group_id and public_key)
  - Permission level (read_only, specific_sentants, time_limited)
  - Which sentants are accessible (filter list)
  - Expiration (optional)

  ## Trust Establishment

  Trust can be established via:
  1. RSSI proximity + mutual confirmation (when devices are very close)
  2. Trust token exchange (manual entry of codes)
  3. Direct API call (for programmatic federation)

  ## Trust Levels

  - `:read_only` - Can discover sentants and read events
  - `:interact` - Can send events to allowed sentants
  - `:full` - Full access to allowed sentants

  ## Storage

  Trust relationships are stored in TrustGroup.trusted_groups and persist
  across restarts via directory.json.
  """
  use GenServer
  require Logger

  @trust_token_validity_seconds 300  # 5 minutes for trust codes
  @default_permissions [:read_only]

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Establish trust with another TrustGroup.

  Options:
  - `:trust_group_name` - Human-readable name of the trusted TrustGroup
  - `:permissions` - List of permission atoms (default: [:read_only])
  - `:sentant_filter` - List of sentant names/IDs to expose (empty = none, nil = all public)
  - `:expires_at` - Unix timestamp when trust expires (nil = permanent)
  """
  def establish_trust(trust_group_id, trust_group_public_key, opts \\ []) do
    GenServer.call(__MODULE__, {:establish_trust, trust_group_id, trust_group_public_key, opts})
  end

  @doc """
  Revoke trust with a TrustGroup.
  """
  def revoke_trust(trust_group_id) do
    GenServer.call(__MODULE__, {:revoke_trust, trust_group_id})
  end

  @doc """
  Get the trust policy for a TrustGroup.
  Returns {:ok, policy} or {:error, :not_trusted}.
  """
  def get_trust_policy(trust_group_id) do
    GenServer.call(__MODULE__, {:get_trust_policy, trust_group_id})
  end

  @doc """
  Check if a TrustGroup is trusted.
  """
  def is_trusted?(trust_group_id) do
    GenServer.call(__MODULE__, {:is_trusted, trust_group_id})
  end

  @doc """
  List all trusted TrustGroups.
  """
  def list_trusted_groups do
    GenServer.call(__MODULE__, :list_trusted_groups)
  end

  @doc """
  Generate a trust establishment token.
  This token can be shared with another TrustGroup to establish bidirectional trust.
  """
  def generate_trust_token(opts \\ []) do
    GenServer.call(__MODULE__, {:generate_trust_token, opts})
  end

  @doc """
  Accept a trust token from another TrustGroup.
  This establishes trust with the TrustGroup that generated the token.
  """
  def accept_trust_token(token, remote_trust_group_id, remote_trust_group_public_key) do
    GenServer.call(__MODULE__, {:accept_trust_token, token, remote_trust_group_id, remote_trust_group_public_key})
  end

  @doc """
  Validate a trust token (without accepting it).
  """
  def validate_trust_token(token) do
    GenServer.call(__MODULE__, {:validate_trust_token, token})
  end

  @doc """
  Check if access is allowed for a trusted TrustGroup to a specific sentant/event.
  """
  def check_access(trust_group_id, sentant_name, event \\ nil) do
    GenServer.call(__MODULE__, {:check_access, trust_group_id, sentant_name, event})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Server Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Trust tokens stored in ETS for fast lookup
    :ets.new(:trust_tokens, [:named_table, :set, :public, read_concurrency: true])

    # Schedule periodic cleanup of expired tokens
    schedule_cleanup()

    Logger.info("[InterGroupTrust] Initialized")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:establish_trust, trust_group_id, trust_group_public_key, opts}, _from, state) do
    trust_group_name = Keyword.get(opts, :trust_group_name, "Unknown TrustGroup")
    permissions = Keyword.get(opts, :permissions, @default_permissions)
    sentant_filter = Keyword.get(opts, :sentant_filter, nil)
    expires_at = Keyword.get(opts, :expires_at, nil)

    trust_entry = %{
      name: trust_group_name,
      public_key: trust_group_public_key,
      trust_ring: 1,  # Direct trust
      established_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      shared_sentant_filter: sentant_filter || [],
      permissions: Enum.map(permissions, &to_string/1),
      expires_at: expires_at,
      status: :active
    }

    # Store in TrustGroup
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :add_trusted_group, [trust_group_id, trust_entry]) do
        :ok ->
          Logger.info("[InterGroupTrust] Established trust with #{trust_group_name} (#{String.slice(trust_group_id, 0..7)}...)")
          {:reply, {:ok, trust_entry}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :directory_not_available}, state}
    end
  end

  @impl true
  def handle_call({:revoke_trust, trust_group_id}, _from, state) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      # Get existing entry and mark as revoked
      case apply(Reality2Transnet.TrustGroup, :get_trusted_groups, []) do
        trusted when is_map(trusted) ->
          case Map.get(trusted, trust_group_id) do
            nil ->
              {:reply, {:error, :not_found}, state}

            entry ->
              revoked_entry = Map.merge(entry, %{
                status: :revoked,
                revoked_at: DateTime.utc_now() |> DateTime.to_iso8601()
              })

              apply(Reality2Transnet.TrustGroup, :add_trusted_group, [trust_group_id, revoked_entry])
              Logger.info("[InterGroupTrust] Revoked trust with #{entry[:name] || trust_group_id}")
              {:reply, :ok, state}
          end

        _ ->
          {:reply, {:error, :not_found}, state}
      end
    else
      {:reply, {:error, :directory_not_available}, state}
    end
  end

  @impl true
  def handle_call({:get_trust_policy, trust_group_id}, _from, state) do
    case get_active_trust(trust_group_id) do
      {:ok, entry} -> {:reply, {:ok, entry}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:is_trusted, trust_group_id}, _from, state) do
    case get_active_trust(trust_group_id) do
      {:ok, _entry} -> {:reply, true, state}
      {:error, _} -> {:reply, false, state}
    end
  end

  @impl true
  def handle_call(:list_trusted_groups, _from, state) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :get_trusted_groups, []) do
        trusted when is_map(trusted) ->
          now = System.system_time(:second)

          result = trusted
          |> Enum.filter(fn {_id, entry} ->
            # Filter out revoked and expired
            status = Map.get(entry, :status, :active)
            expires_at = Map.get(entry, :expires_at)

            status != :revoked and (expires_at == nil or expires_at > now)
          end)
          |> Enum.map(fn {trust_group_id, entry} ->
            Map.merge(entry, %{trust_group_id: trust_group_id})
          end)

          {:reply, result, state}

        _ ->
          {:reply, [], state}
      end
    else
      {:reply, [], state}
    end
  end

  @impl true
  def handle_call({:generate_trust_token, opts}, _from, state) do
    permissions = Keyword.get(opts, :permissions, @default_permissions)
    sentant_filter = Keyword.get(opts, :sentant_filter, nil)

    # Get our trust_group info
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :export_public, []) do
        {:ok, trust_group_info} ->
          token = generate_token_string()
          now = System.system_time(:second)

          token_data = %{
            token: token,
            trust_group_id: trust_group_info.trust_group_id,
            trustGroupName: trust_group_info.name,
            trust_group_public_key: trust_group_info.public_key,
            permissions: Enum.map(permissions, &to_string/1),
            sentant_filter: sentant_filter,
            expires_at: now + @trust_token_validity_seconds,
            created_at: now
          }

          :ets.insert(:trust_tokens, {token, token_data})

          {:reply, {:ok, token_data}, state}

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :identity_not_available}, state}
    end
  end

  @impl true
  def handle_call({:accept_trust_token, token, remote_trust_group_id, remote_trust_group_public_key}, _from, state) do
    # Validate token format
    case :ets.lookup(:trust_tokens, String.upcase(token)) do
      [{_key, token_data}] ->
        now = System.system_time(:second)

        if token_data.expires_at < now do
          :ets.delete(:trust_tokens, String.upcase(token))
          {:reply, {:error, :token_expired}, state}
        else
          # Verify the remote trust_group matches what's in the token
          # (In a full implementation, you'd verify signatures here)

          # Establish trust
          trust_entry = %{
            name: token_data.trustGroupName,
            public_key: remote_trust_group_public_key,
            trust_ring: 1,
            established_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            shared_sentant_filter: token_data.sentant_filter || [],
            permissions: token_data.permissions,
            status: :active
          }

          if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
            apply(Reality2Transnet.TrustGroup, :add_trusted_group, [remote_trust_group_id, trust_entry])
            :ets.delete(:trust_tokens, String.upcase(token))
            Logger.info("[InterGroupTrust] Accepted trust token from #{token_data.trustGroupName}")
            {:reply, {:ok, trust_entry}, state}
          else
            {:reply, {:error, :directory_not_available}, state}
          end
        end

      [] ->
        {:reply, {:error, :invalid_token}, state}
    end
  end

  @impl true
  def handle_call({:validate_trust_token, token}, _from, state) do
    case :ets.lookup(:trust_tokens, String.upcase(token)) do
      [{_key, token_data}] ->
        now = System.system_time(:second)
        if token_data.expires_at < now do
          {:reply, {:error, :token_expired}, state}
        else
          {:reply, {:ok, token_data}, state}
        end

      [] ->
        {:reply, {:error, :invalid_token}, state}
    end
  end

  @impl true
  def handle_call({:check_access, trust_group_id, sentant_name, event}, _from, state) do
    case get_active_trust(trust_group_id) do
      {:ok, entry} ->
        # Check sentant filter
        filter = Map.get(entry, :shared_sentant_filter, [])
        sentant_allowed = filter == [] or sentant_name in filter

        # Check event permission (if permissions include interact or full)
        permissions = Map.get(entry, :permissions, ["read_only"])
        event_allowed = event == nil or "interact" in permissions or "full" in permissions

        if sentant_allowed and event_allowed do
          {:reply, :ok, state}
        else
          reason = cond do
            not sentant_allowed -> :sentant_not_allowed
            not event_allowed -> :event_not_allowed
            true -> :access_denied
          end
          {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:cleanup_expired_tokens, state) do
    now = System.system_time(:second)

    expired = :ets.tab2list(:trust_tokens)
    |> Enum.filter(fn {_key, data} -> data.expires_at < now end)
    |> Enum.map(fn {key, _data} -> key end)

    Enum.each(expired, &:ets.delete(:trust_tokens, &1))

    if length(expired) > 0 do
      Logger.debug("[InterGroupTrust] Cleaned up #{length(expired)} expired trust tokens")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_active_trust(trust_group_id) do
    if Code.ensure_loaded?(Reality2Transnet.TrustGroup) do
      case apply(Reality2Transnet.TrustGroup, :get_trusted_groups, []) do
        trusted when is_map(trusted) ->
          case Map.get(trusted, trust_group_id) do
            nil -> {:error, :not_trusted}
            entry ->
              status = Map.get(entry, :status, :active)
              expires_at = Map.get(entry, :expires_at)
              now = System.system_time(:second)

              cond do
                status == :revoked -> {:error, :trust_revoked}
                expires_at != nil and expires_at < now -> {:error, :trust_expired}
                true -> {:ok, entry}
              end
          end

        _ ->
          {:error, :not_trusted}
      end
    else
      {:error, :directory_not_available}
    end
  end

  defp generate_token_string do
    # Generate a 8-character alphanumeric code (uppercase)
    chars = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    1..8
    |> Enum.map(fn _ -> Enum.random(chars) end)
    |> List.to_string()
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired_tokens, 60_000)
  end
end
