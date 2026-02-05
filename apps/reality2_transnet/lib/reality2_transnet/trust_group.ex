defmodule Reality2Transnet.TrustGroup do
  @moduledoc """
  Cryptographic identity for a Trust Group (Human Interactive Virtual Experience).

  A Trust Group is a collection of nodes acting as a single unified identity. The Trust Group ID
  is derived from a public key, making it self-certifying - you cannot claim to be
  a Trust Group without possessing its private key.

  ## Key Concepts

  - **Trust Group ID**: UUID derived from public key hash (the ONLY stable identifier)
  - **Trust Group Name**: Human-readable name (can be changed)
  - **Node Certificates**: Signed documents proving node membership in a Trust Group
  - **Ed25519**: Fast, compact signatures (64 bytes) for mesh communication

  ## Node Modes

  A node can operate in two modes:

  1. **Key Holder** (`:key_holder`) - Has the Trust Group private key, can:
     - Issue node certificates
     - Sign messages as the Trust Group
     - Bootstrap new nodes into the Trust Group

  2. **Member** (`:member`) - Only has a node certificate, can:
     - Prove membership via certificate
     - Verify other nodes' certificates
     - Sign messages with own node key

  ## Key Management

  The Trust Group private key is precious - it's the identity itself. Strategies:

  - **Single key holder**: One device holds the key (simplest, least resilient)
  - **Multiple key holders**: Key replicated to trusted devices
  - **Backup**: Key exported to secure storage (encrypted USB, cloud)
  - **Recovery**: Import key to new device if original is lost

  ## Usage

      # Generate a new Trust Group identity
      {:ok, identity} = TrustGroup.generate("MyTrustGroup")

      # Sign a message
      signature = TrustGroup.sign(identity, "hello")

      # Verify a signature
      true = TrustGroup.verify(identity.public_key, "hello", signature)

      # Issue a certificate for a node
      {:ok, cert} = TrustGroup.issue_node_cert(identity, "laptop", node_pub_key)

      # Verify a node certificate
      {:ok, node_info} = TrustGroup.verify_node_cert(cert, identity.public_key)

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  import Bitwise
  require Logger

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Types
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc "Node operating mode"
  @type node_mode :: :key_holder | :member

  @typedoc "Trust Group identity structure"
  @type t :: %__MODULE__{
    trust_group_id: String.t(),
    name: String.t(),
    public_key: binary(),
    private_key: binary() | nil,
    algorithm: :ed25519,
    created_at: DateTime.t(),
    mode: node_mode(),
    node_name: String.t() | nil,
    node_cert: node_cert() | nil,
    provisional: boolean(),
    active_join_codes: map()
  }

  @typedoc "Node certificate issued by a Trust Group"
  @type node_cert :: %{
    type: :node_cert,
    version: non_neg_integer(),
    trust_group_id: String.t(),
    node_name: String.t(),
    node_public_key: binary(),
    permissions: [atom()],
    issued_at: non_neg_integer(),
    expires_at: non_neg_integer() | :never,
    signature: binary()
  }

  defstruct [
    :trust_group_id,
    :name,
    :public_key,
    :private_key,
    :algorithm,
    :created_at,
    mode: :key_holder,
    node_name: nil,
    node_cert: nil,
    # Provisional = just created, trust-group-of-one, may want to join another
    provisional: true,
    # Join codes for pairing new devices
    active_join_codes: %{}
  ]

  # Certificate validity period (1 year in seconds)
  @default_cert_validity 365 * 24 * 60 * 60
  @cert_version 1

  # Auto-establish provisional trust groups after 24 hours
  @auto_establish_hours 24
  @auto_establish_check_interval 60 * 60 * 1000  # Check every hour in ms

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Starts the TrustGroup GenServer.

  On startup, attempts to load existing identity from disk, or generates a new one.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current Trust Group identity.
  """
  @spec get_identity() :: {:ok, t()} | {:error, :not_initialized}
  def get_identity do
    GenServer.call(__MODULE__, :get_identity)
  end

  @doc """
  Returns just the Trust Group ID.
  """
  @spec get_trust_group_id() :: {:ok, String.t()} | {:error, :not_initialized}
  def get_trust_group_id do
    case get_identity() do
      {:ok, identity} -> {:ok, identity.trust_group_id}
      error -> error
    end
  end

  @doc """
  Returns the public key for external verification.
  """
  @spec get_public_key() :: {:ok, binary()} | {:error, :not_initialized}
  def get_public_key do
    case get_identity() do
      {:ok, identity} -> {:ok, identity.public_key}
      error -> error
    end
  end

  @doc """
  Signs data with the Trust Group's private key.
  """
  @spec sign_data(binary()) :: {:ok, binary()} | {:error, term()}
  def sign_data(data) when is_binary(data) do
    GenServer.call(__MODULE__, {:sign, data})
  end

  @doc """
  Issues a node certificate for a node joining this Trust Group.
  Only works if this node is a key holder.
  """
  @spec issue_cert(String.t(), binary(), keyword()) :: {:ok, node_cert()} | {:error, term()}
  def issue_cert(node_name, node_public_key, opts \\ []) do
    GenServer.call(__MODULE__, {:issue_cert, node_name, node_public_key, opts})
  end

  @doc """
  Returns the current node mode (:key_holder or :member).
  """
  @spec get_mode() :: {:ok, node_mode()} | {:error, :not_initialized}
  def get_mode do
    case get_identity() do
      {:ok, identity} -> {:ok, identity.mode}
      error -> error
    end
  end

  @doc """
  Checks if this node can issue certificates (is a key holder).
  """
  @spec is_key_holder?() :: boolean()
  def is_key_holder? do
    case get_mode() do
      {:ok, :key_holder} -> true
      _ -> false
    end
  end

  @doc """
  Exports the Trust Group private key (for backup or transfer to another device).
  Returns encrypted key data that can be imported elsewhere.

  ## Parameters
  - `passphrase` - Passphrase to encrypt the export

  ## Returns
  - `{:ok, encrypted_data}` - Base64-encoded encrypted key bundle
  - `{:error, :not_key_holder}` - This node doesn't hold the key
  """
  @spec export_key(String.t()) :: {:ok, String.t()} | {:error, term()}
  def export_key(passphrase) when is_binary(passphrase) do
    GenServer.call(__MODULE__, {:export_key, passphrase})
  end

  @doc """
  Imports a Trust Group private key (to become a key holder).
  Use this to restore a Trust Group identity or replicate it to another device.

  ## Parameters
  - `encrypted_data` - Base64-encoded encrypted key bundle
  - `passphrase` - Passphrase to decrypt

  ## Returns
  - `:ok` - Key imported successfully
  - `{:error, :already_key_holder}` - Already holding a key
  - `{:error, :invalid_passphrase}` - Wrong passphrase
  """
  @spec import_key(String.t(), String.t()) :: :ok | {:error, term()}
  def import_key(encrypted_data, passphrase) do
    GenServer.call(__MODULE__, {:import_key, encrypted_data, passphrase})
  end

  @doc """
  Joins an existing Trust Group as a member (not a key holder).
  The node will generate its own keypair and store the certificate.

  ## Parameters
  - `trust_group_public_info` - Map with trust_group_id, name, public_key (from key holder)
  - `node_cert` - Certificate issued by a key holder for this node

  ## Returns
  - `:ok` - Successfully joined as member
  - `{:error, :invalid_cert}` - Certificate doesn't verify
  """
  @spec join_as_member(map(), node_cert()) :: :ok | {:error, term()}
  def join_as_member(trust_group_public_info, node_cert) do
    GenServer.call(__MODULE__, {:join_as_member, trust_group_public_info, node_cert})
  end

  @doc """
  Restores a Trust Group identity from an encrypted backup.

  Use this for disaster recovery when all devices are lost but you have
  a backup of the Trust Group key (from `export_key/1`).

  WARNING: This replaces the current identity entirely!

  ## Parameters
  - `encrypted_data` - Base64-encoded encrypted key bundle from `export_key/1`
  - `passphrase` - Passphrase used when creating the backup

  ## Returns
  - `{:ok, trust_group_id}` - Successfully restored, returns the Trust Group ID
  - `{:error, :invalid_passphrase}` - Wrong passphrase
  - `{:error, :invalid_format}` - Corrupted backup data
  """
  @spec restore_from_backup(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def restore_from_backup(encrypted_data, passphrase) do
    GenServer.call(__MODULE__, {:restore_from_backup, encrypted_data, passphrase})
  end

  @doc """
  Returns the raw private key as a Base64 string.

  This is the simplest backup - just copy this string to a password manager.
  The Trust Group ID and public key can be derived from this.

  Example output: "nCtYTVf3s2q3pshjFc6L//90yCTRoZTN8RX0eX1sPPo="

  ## Returns
  - `{:ok, base64_key}` - The private key (44 characters)
  - `{:error, :not_key_holder}` - This node doesn't hold the key
  """
  @spec get_private_key() :: {:ok, String.t()} | {:error, term()}
  def get_private_key do
    GenServer.call(__MODULE__, :get_private_key)
  end

  @doc """
  Restores a Trust Group from just the private key (from `get_private_key/0`).

  Use this when you've stored the raw key in a password manager.

  WARNING: This replaces the current identity entirely!

  ## Parameters
  - `private_key_b64` - Base64-encoded private key (44 characters)
  - `name` - Name for the Trust Group (optional, defaults to "RestoredTrustGroup")

  ## Returns
  - `{:ok, trust_group_id}` - Successfully restored
  - `{:error, :invalid_key}` - Invalid key format
  """
  @spec restore_from_private_key(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def restore_from_private_key(private_key_b64, name \\ "RestoredTrustGroup") do
    GenServer.call(__MODULE__, {:restore_from_private_key, private_key_b64, name})
  end

  @doc """
  Creates a new Trust Group identity, replacing any existing one.

  WARNING: This is destructive! The old Trust Group identity will be lost forever
  unless you have a backup from `export_key/1`.

  ## Parameters
  - `name` - Human-readable name for the new Trust Group

  ## Returns
  - `{:ok, trust_group_id}` - New Trust Group created, returns the new Trust Group ID
  """
  @spec reset_trust_group(String.t()) :: {:ok, String.t()}
  def reset_trust_group(name) when is_binary(name) do
    GenServer.call(__MODULE__, {:reset_trust_group, name})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Trust Group Joining API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Derives an encryption key for a specific purpose from the Trust Group private key.

  Use this for Trust Group-scoped data encryption. When a device leaves the Trust Group,
  it loses access to data encrypted with the Trust Group-derived key.

  ## Parameters
  - `purpose` - String identifying what this key is for (e.g., "backup", "sentant:mysentant")

  ## Returns
  - `{:ok, base64_key}` - 32-byte AES key, base64-encoded (for Reality2.Helpers.Crypto)
  - `{:error, :not_key_holder}` - Only key holders can derive keys

  ## Example

      # Crypto module uses this internally:
      {:ok, encrypted} = Reality2.Helpers.Crypto.encrypt(data, "backup:passwords")
      {:ok, decrypted} = Reality2.Helpers.Crypto.decrypt(encrypted, "backup:passwords")
  """
  @spec derive_data_key(String.t()) :: {:ok, String.t()} | {:error, term()}
  def derive_data_key(purpose) when is_binary(purpose) do
    GenServer.call(__MODULE__, {:derive_data_key, purpose})
  end

  @doc """
  Checks if this Trust Group is provisional (just created, trust-group-of-one).

  Provisional Trust Groups may want to join an established Trust Group instead.
  """
  @spec is_provisional?() :: boolean()
  def is_provisional? do
    case get_identity() do
      {:ok, identity} -> identity.provisional
      _ -> false
    end
  end

  @doc """
  Marks this Trust Group as established (no longer provisional).

  Call this when the user confirms they want to keep their own Trust Group
  rather than joining another.
  """
  @spec mark_established() :: :ok
  def mark_established do
    GenServer.call(__MODULE__, :mark_established)
  end

  @doc """
  Generates a short-lived join code for pairing a new device.

  The code is valid for 5 minutes. Share it with the device wanting to join.

  ## Returns
  - `{:ok, code}` - 4-character alphanumeric code (e.g., "A7X9")
  - `{:error, :not_key_holder}` - Only key holders can generate codes
  """
  @spec generate_join_code() :: {:ok, String.t()} | {:error, term()}
  def generate_join_code do
    GenServer.call(__MODULE__, :generate_join_code)
  end

  @doc """
  Verifies a join code and returns Trust Group info if valid.

  Called by the joining device after receiving a code.

  ## Parameters
  - `code` - The 4-character join code

  ## Returns
  - `{:ok, trust_group_info}` - Code valid, returns public Trust Group info
  - `{:error, :invalid_code}` - Code not found or expired
  """
  @spec verify_join_code(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_join_code(code) do
    GenServer.call(__MODULE__, {:verify_join_code, code})
  end

  @doc """
  Requests to join another Trust Group using a join code.

  This abandons the current (provisional) Trust Group and joins the target Trust Group.
  The key holder must have generated the code via `generate_join_code/0`.

  ## Parameters
  - `target_node_id` - Node ID of a key holder in the target Trust Group
  - `join_code` - The 4-character code from the key holder
  - `my_node_name` - Name for this node in the new Trust Group

  ## Returns
  - `{:ok, trust_group_id}` - Successfully joined, returns new Trust Group ID
  - `{:error, :invalid_code}` - Code invalid or expired
  - `{:error, :not_provisional}` - Can only join if currently provisional
  """
  @spec request_join(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def request_join(target_node_id, join_code, my_node_name) do
    GenServer.call(__MODULE__, {:request_join, target_node_id, join_code, my_node_name}, 30_000)
  end

  @doc """
  Processes a join request from another device (called on key holder).

  This is called via mesh when a device requests to join using our code.

  ## Parameters
  - `requester_node_id` - Node ID of the requesting device
  - `join_code` - The code they're using
  - `node_name` - Requested name for the new node
  - `node_public_key` - Public key of the new node

  ## Returns
  - `{:ok, certificate}` - Approved, returns signed certificate
  - `{:error, reason}` - Rejected
  """
  @spec process_join_request(String.t(), String.t(), String.t(), binary()) :: {:ok, node_cert()} | {:error, term()}
  def process_join_request(requester_node_id, join_code, node_name, node_public_key) do
    GenServer.call(__MODULE__, {:process_join_request, requester_node_id, join_code, node_name, node_public_key})
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(opts) do
    trust_group_name = Keyword.get(opts, :name) || get_configured_name()
    data_dir = get_data_dir()

    identity = case load_identity(data_dir) do
      {:ok, loaded} ->
        Logger.info("[TrustGroup] Loaded existing identity: #{loaded.trust_group_id}")
        loaded

      {:error, _} ->
        Logger.info("[TrustGroup] Generating new identity for Trust Group: #{trust_group_name}")
        {:ok, new_identity} = generate(trust_group_name)
        save_identity(new_identity, data_dir)
        new_identity
    end

    # Schedule periodic check for auto-establishing provisional trust groups
    schedule_auto_establish_check()

    # Register with KeyHolders if we're a key holder (deferred to allow KeyHolders to start)
    if identity.mode == :key_holder do
      Process.send_after(self(), :register_as_key_holder, 1000)
    end

    {:ok, %{identity: identity, data_dir: data_dir}}
  end

  @impl true
  def handle_call(:get_identity, _from, %{identity: identity} = state) do
    {:reply, {:ok, identity}, state}
  end

  @impl true
  def handle_call({:sign, data}, _from, %{identity: identity} = state) do
    case identity.mode do
      :key_holder ->
        result = sign(identity, data)
        {:reply, {:ok, result}, state}

      :member ->
        {:reply, {:error, :not_key_holder}, state}
    end
  end

  @impl true
  def handle_call({:issue_cert, node_name, node_public_key, opts}, _from, %{identity: identity} = state) do
    case identity.mode do
      :key_holder ->
        result = issue_node_cert(identity, node_name, node_public_key, opts)
        {:reply, result, state}

      :member ->
        {:reply, {:error, :not_key_holder}, state}
    end
  end

  @impl true
  def handle_call({:export_key, passphrase}, _from, %{identity: identity} = state) do
    case identity.mode do
      :key_holder ->
        result = encrypt_key_bundle(identity, passphrase)
        {:reply, result, state}

      :member ->
        {:reply, {:error, :not_key_holder}, state}
    end
  end

  @impl true
  def handle_call({:import_key, encrypted_data, passphrase}, _from, %{identity: identity, data_dir: data_dir} = state) do
    case identity.mode do
      :key_holder ->
        {:reply, {:error, :already_key_holder}, state}

      :member ->
        case decrypt_key_bundle(encrypted_data, passphrase) do
          {:ok, imported_identity} ->
            # Verify the imported key matches this Trust Group
            if imported_identity.trust_group_id == identity.trust_group_id do
              new_identity = %{imported_identity | mode: :key_holder}
              save_identity(new_identity, data_dir)
              Logger.info("[TrustGroup] Promoted to key holder for Trust Group: #{new_identity.trust_group_id}")
              {:reply, :ok, %{state | identity: new_identity}}
            else
              {:reply, {:error, :trust_group_mismatch}, state}
            end

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:join_as_member, trust_group_public_info, node_cert}, _from, %{data_dir: data_dir} = state) do
    with {:ok, public_identity} <- from_public(trust_group_public_info),
         {:ok, _cert_data} <- verify_node_cert(node_cert, public_identity.public_key) do

      # Extract node name from certificate
      node_name = node_cert.node_name

      member_identity = %__MODULE__{
        trust_group_id: public_identity.trust_group_id,
        name: public_identity.name,
        public_key: public_identity.public_key,
        private_key: nil,
        algorithm: :ed25519,
        created_at: public_identity.created_at,
        mode: :member,
        node_name: node_name,
        node_cert: node_cert
      }

      save_member_identity(member_identity, data_dir)
      Logger.info("[TrustGroup] Joined Trust Group #{public_identity.trust_group_id} as member node: #{node_name}")

      # Refresh the BLE beacon to advertise new trust group membership
      if Code.ensure_loaded?(Reality2Transnet.Bluetooth) do
        spawn(fn -> Reality2Transnet.Bluetooth.refresh_beacon() end)
      end

      {:reply, :ok, %{state | identity: member_identity}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:restore_from_backup, encrypted_data, passphrase}, _from, %{data_dir: data_dir} = state) do
    case decrypt_key_bundle(encrypted_data, passphrase) do
      {:ok, restored_identity} ->
        save_identity(restored_identity, data_dir)
        Logger.info("[TrustGroup] Restored Trust Group from backup: #{restored_identity.trust_group_id}")

        # Refresh the BLE beacon to advertise restored trust group membership
        if Code.ensure_loaded?(Reality2Transnet.Bluetooth) do
          spawn(fn -> Reality2Transnet.Bluetooth.refresh_beacon() end)
        end

        {:reply, {:ok, restored_identity.trust_group_id}, %{state | identity: restored_identity}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_private_key, _from, %{identity: identity} = state) do
    case identity.mode do
      :key_holder ->
        {:reply, {:ok, Base.encode64(identity.private_key)}, state}

      :member ->
        {:reply, {:error, :not_key_holder}, state}
    end
  end

  @impl true
  def handle_call({:restore_from_private_key, private_key_b64, name}, _from, %{data_dir: data_dir} = state) do
    case Base.decode64(private_key_b64) do
      {:ok, private_key} when byte_size(private_key) == 32 ->
        # Derive public key from private key
        # In Ed25519, we need to regenerate the keypair from the seed
        {public_key, ^private_key} = :crypto.generate_key(:eddsa, :ed25519, private_key)
        trust_group_id = derive_trust_group_id(public_key)

        restored_identity = %__MODULE__{
          trust_group_id: trust_group_id,
          name: name,
          public_key: public_key,
          private_key: private_key,
          algorithm: :ed25519,
          created_at: DateTime.utc_now(),
          mode: :key_holder
        }

        save_identity(restored_identity, data_dir)
        Logger.info("[TrustGroup] Restored Trust Group from private key: #{trust_group_id}")
        {:reply, {:ok, trust_group_id}, %{state | identity: restored_identity}}

      {:ok, _} ->
        {:reply, {:error, :invalid_key_size}, state}

      :error ->
        {:reply, {:error, :invalid_key}, state}
    end
  end

  @impl true
  def handle_call({:reset_trust_group, name}, _from, %{data_dir: data_dir} = state) do
    {:ok, new_identity} = generate(name)
    save_identity(new_identity, data_dir)
    Logger.info("[TrustGroup] Created new Trust Group: #{new_identity.trust_group_id} (name: #{name})")

    # Refresh the BLE beacon to advertise new trust group membership
    if Code.ensure_loaded?(Reality2Transnet.Bluetooth) do
      spawn(fn -> Reality2Transnet.Bluetooth.refresh_beacon() end)
    end

    {:reply, {:ok, new_identity.trust_group_id}, %{state | identity: new_identity}}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Trust Group Key Derivation Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call({:derive_data_key, purpose}, _from, %{identity: identity} = state) do
    case identity.mode do
      :key_holder ->
        # Use HKDF to derive a purpose-specific key from the Trust Group private key
        # This ensures different purposes get different keys
        info = "trust-group-data-key:" <> purpose
        derived = :crypto.mac(:hmac, :sha256, identity.private_key, info)
        {:reply, {:ok, Base.encode64(derived)}, state}

      :member ->
        {:reply, {:error, :not_key_holder}, state}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Trust Group Joining Handlers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_call(:mark_established, _from, %{identity: identity, data_dir: data_dir} = state) do
    updated = %{identity | provisional: false}
    save_identity(updated, data_dir)
    Logger.info("[TrustGroup] Trust Group marked as established: #{identity.trust_group_id}")
    {:reply, :ok, %{state | identity: updated}}
  end

  @impl true
  def handle_call(:generate_join_code, _from, %{identity: identity} = state) do
    case identity.mode do
      :key_holder ->
        # Generate 4-character code
        code = generate_code()
        expires_at = System.system_time(:second) + 300  # 5 minutes

        # Store in active codes
        updated_codes = Map.put(identity.active_join_codes, code, %{
          expires_at: expires_at,
          created_at: System.system_time(:second)
        })
        updated = %{identity | active_join_codes: updated_codes}

        Logger.info("[TrustGroup] Generated join code: #{code} (expires in 5 min)")
        {:reply, {:ok, code}, %{state | identity: updated}}

      :member ->
        {:reply, {:error, :not_key_holder}, state}
    end
  end

  @impl true
  def handle_call({:verify_join_code, code}, _from, %{identity: identity} = state) do
    now = System.system_time(:second)

    case Map.get(identity.active_join_codes, String.upcase(code)) do
      %{expires_at: expires} when expires > now ->
        trust_group_info = %{
          trustGroupId: identity.trust_group_id,
          trustGroupName: identity.name,
          trust_group_public_key: Base.encode64(identity.public_key),
          created_at: DateTime.to_iso8601(identity.created_at)
        }
        {:reply, {:ok, trust_group_info}, state}

      _ ->
        {:reply, {:error, :invalid_code}, state}
    end
  end

  @impl true
  def handle_call({:process_join_request, _requester_id, code, node_name, node_public_key}, _from, %{identity: identity} = state) do
    now = System.system_time(:second)
    code_upper = String.upcase(code)

    case Map.get(identity.active_join_codes, code_upper) do
      %{expires_at: expires} when expires > now ->
        # Valid code - issue certificate
        case issue_node_cert(identity, node_name, node_public_key) do
          {:ok, cert} ->
            # Remove used code
            updated_codes = Map.delete(identity.active_join_codes, code_upper)
            updated = %{identity | active_join_codes: updated_codes, provisional: false}

            Logger.info("[TrustGroup] Issued certificate for node '#{node_name}' joining Trust Group")
            {:reply, {:ok, cert}, %{state | identity: updated}}

          error ->
            {:reply, error, state}
        end

      _ ->
        {:reply, {:error, :invalid_code}, state}
    end
  end

  @impl true
  def handle_call({:request_join, _target_node_id, _join_code, _my_node_name}, _from, %{identity: identity} = state) do
    # Note: The actual mesh communication for joining is handled separately
    # This just checks if we're allowed to join
    if identity.provisional do
      # The actual join happens via mesh message exchange
      # This is a placeholder - real implementation needs mesh coordination
      {:reply, {:error, :use_mesh_join}, state}
    else
      {:reply, {:error, :not_provisional}, state}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Handle Info - Periodic Tasks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_info(:check_auto_establish, %{identity: identity, data_dir: data_dir} = state) do
    state = if identity.provisional and should_auto_establish?(identity) do
      Logger.info("[TrustGroup] Auto-establishing provisional trust group after #{@auto_establish_hours}h: #{identity.trust_group_id}")
      updated = %{identity | provisional: false}
      save_identity(updated, data_dir)
      %{state | identity: updated}
    else
      state
    end

    # Schedule next check
    schedule_auto_establish_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(:register_as_key_holder, state) do
    # Register with KeyHolders module if available
    # Use whereis to check if process is running to avoid blocking on unstarted process
    if Code.ensure_loaded?(Reality2Transnet.KeyHolders) do
      case GenServer.whereis(Reality2Transnet.KeyHolders) do
        nil ->
          # KeyHolders not started yet, retry in 2 seconds
          Process.send_after(self(), :register_as_key_holder, 2000)
          Logger.debug("[TrustGroup] KeyHolders not ready, will retry in 2s")

        _pid ->
          try do
            case Reality2Transnet.KeyHolders.register_local() do
              :ok -> Logger.info("[TrustGroup] Registered as key holder with KeyHolders module")
              {:error, reason} -> Logger.warning("[TrustGroup] Failed to register as key holder: #{inspect(reason)}")
            end
          rescue
            e -> Logger.warning("[TrustGroup] KeyHolders registration error: #{inspect(e)}")
          catch
            :exit, _ -> Logger.warning("[TrustGroup] KeyHolders registration failed (process exited)")
          end
      end
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions - Identity Generation
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Generates a new Trust Group identity with Ed25519 keypair.

  ## Parameters
  - `name` - Human-readable name for the Trust Group

  ## Returns
  - `{:ok, identity}` - New identity with generated keys
  """
  @spec generate(String.t()) :: {:ok, t()}
  def generate(name) when is_binary(name) do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    trust_group_id = derive_trust_group_id(public_key)

    identity = %__MODULE__{
      trust_group_id: trust_group_id,
      name: name,
      public_key: public_key,
      private_key: private_key,
      algorithm: :ed25519,
      created_at: DateTime.utc_now()
    }

    {:ok, identity}
  end

  @doc """
  Derives a Trust Group ID (UUID) from a public key.

  The Trust Group ID is a UUID v5 derived from the SHA-256 hash of the public key.
  This ensures the ID is deterministic and self-certifying.

  ## Parameters
  - `public_key` - Ed25519 public key (32 bytes)

  ## Returns
  - UUID string in standard format (8-4-4-4-12)
  """
  @spec derive_trust_group_id(binary()) :: String.t()
  def derive_trust_group_id(public_key) when is_binary(public_key) do
    # Hash the public key
    hash = :crypto.hash(:sha256, public_key)

    # Take first 16 bytes and format as UUID v5
    <<a::32, b::16, c::16, d::16, e::48>> = binary_part(hash, 0, 16)

    # Set version (5) and variant (RFC 4122)
    c_versioned = (c &&& 0x0FFF) ||| 0x5000
    d_variant = (d &&& 0x3FFF) ||| 0x8000

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c_versioned, d_variant, e]
    )
    |> IO.iodata_to_binary()
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions - Cryptographic Operations
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Signs a message with the identity's private key.

  ## Parameters
  - `identity` - Trust Group identity with private key
  - `message` - Data to sign (binary or string)

  ## Returns
  - 64-byte Ed25519 signature
  """
  @spec sign(t(), binary() | String.t()) :: binary()
  def sign(%__MODULE__{private_key: private_key, algorithm: :ed25519}, message)
      when is_binary(message) and not is_nil(private_key) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
  end

  def sign(%__MODULE__{private_key: private_key}, message)
      when is_binary(message) and not is_nil(private_key) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
  end

  @doc """
  Verifies a signature against a public key.

  ## Parameters
  - `public_key` - Ed25519 public key (32 bytes)
  - `message` - Original message
  - `signature` - 64-byte signature to verify

  ## Returns
  - `true` if valid
  - `false` if invalid
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(public_key, message, signature)
      when is_binary(public_key) and is_binary(message) and is_binary(signature) do
    :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
  rescue
    _ -> false
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions - Node Certificates
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Issues a node certificate proving a node belongs to this Trust Group.

  The certificate is signed by the Trust Group's private key and can be verified
  by anyone with the Trust Group's public key.

  ## Parameters
  - `identity` - Trust Group identity (with private key)
  - `node_name` - Name of the node (unique within Trust Group)
  - `node_public_key` - Node's Ed25519 public key
  - `opts` - Options:
    - `:permissions` - List of permission atoms (default: [:full])
    - `:validity` - Validity period in seconds (default: 1 year)

  ## Returns
  - `{:ok, certificate}` - Signed certificate map
  - `{:error, reason}` - If signing fails
  """
  @spec issue_node_cert(t(), String.t(), binary(), keyword()) :: {:ok, node_cert()} | {:error, term()}
  def issue_node_cert(%__MODULE__{} = identity, node_name, node_public_key, opts \\ []) do
    permissions = Keyword.get(opts, :permissions, [:full])
    validity = Keyword.get(opts, :validity, @default_cert_validity)

    now = System.system_time(:second)
    expires = if validity == :never, do: :never, else: now + validity

    # Build certificate data (without signature)
    cert_data = %{
      type: :node_cert,
      version: @cert_version,
      trust_group_id: identity.trust_group_id,
      node_name: node_name,
      node_public_key: Base.encode64(node_public_key),
      permissions: permissions,
      issued_at: now,
      expires_at: expires
    }

    # Create canonical representation for signing
    signable = cert_to_signable(cert_data)

    # Sign with Trust Group private key
    signature = sign(identity, signable)

    cert = Map.put(cert_data, :signature, Base.encode64(signature))
    {:ok, cert}
  end

  @doc """
  Verifies a node certificate was issued by the given Trust Group.

  ## Parameters
  - `cert` - Certificate map
  - `trust_group_public_key` - Trust Group's public key for verification

  ## Returns
  - `{:ok, cert_data}` - Certificate is valid
  - `{:error, :invalid_signature}` - Signature doesn't match
  - `{:error, :expired}` - Certificate has expired
  - `{:error, :invalid_format}` - Certificate format is wrong
  """
  @spec verify_node_cert(map() | binary(), binary()) :: {:ok, map()} | {:error, term()}
  def verify_node_cert(cert, trust_group_public_key) when is_map(cert) do
    with {:ok, signature} <- decode_signature(cert),
         {:ok, _} <- check_expiry(cert),
         cert_data <- Map.delete(cert, :signature),
         signable <- cert_to_signable(cert_data),
         true <- verify(trust_group_public_key, signable, signature) do
      {:ok, cert_data}
    else
      false -> {:error, :invalid_signature}
      error -> error
    end
  end

  def verify_node_cert(cert_json, trust_group_public_key) when is_binary(cert_json) do
    case Jason.decode(cert_json, keys: :atoms) do
      {:ok, cert} -> verify_node_cert(cert, trust_group_public_key)
      _ -> {:error, :invalid_format}
    end
  end

  @doc """
  Extracts the node public key from a certificate.
  """
  @spec get_node_public_key(node_cert()) :: {:ok, binary()} | {:error, term()}
  def get_node_public_key(%{node_public_key: encoded}) when is_binary(encoded) do
    Base.decode64(encoded)
  end
  def get_node_public_key(_), do: {:error, :invalid_cert}

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions - Serialization
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Exports the identity to a map (without private key for sharing).
  """
  @spec export_public(t()) :: map()
  def export_public(%__MODULE__{} = identity) do
    %{
      trust_group_id: identity.trust_group_id,
      name: identity.name,
      public_key: Base.encode64(identity.public_key),
      algorithm: identity.algorithm,
      created_at: DateTime.to_iso8601(identity.created_at)
    }
  end

  @doc """
  Creates an identity struct from public information (for peer verification).
  """
  @spec from_public(map()) :: {:ok, t()} | {:error, term()}
  def from_public(%{trust_group_id: trust_group_id, public_key: pub_key_b64} = data) do
    with {:ok, public_key} <- Base.decode64(pub_key_b64),
         ^trust_group_id <- derive_trust_group_id(public_key) do
      {:ok, %__MODULE__{
        trust_group_id: trust_group_id,
        name: Map.get(data, :name, "unknown"),
        public_key: public_key,
        private_key: nil,
        algorithm: :ed25519,
        created_at: parse_datetime(data[:created_at])
      }}
    else
      _ -> {:error, :invalid_identity}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Persistence
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_data_dir do
    Application.get_env(:reality2_transnet, :trust_group_data_dir, ".r2")
  end

  defp get_configured_name do
    Application.get_env(:reality2_transnet, :trust_group_name, "DefaultTrustGroup")
  end

  defp schedule_auto_establish_check do
    Process.send_after(self(), :check_auto_establish, @auto_establish_check_interval)
  end

  defp should_auto_establish?(%__MODULE__{created_at: created_at}) do
    case created_at do
      %DateTime{} = dt ->
        elapsed_seconds = DateTime.utc_now() |> DateTime.diff(dt, :second)
        elapsed_seconds >= (@auto_establish_hours * 60 * 60)
      _ ->
        # If created_at is missing or invalid, don't auto-establish
        false
    end
  end

  defp identity_path(data_dir) do
    Path.join(data_dir, "identity.json")
  end

  defp save_identity(%__MODULE__{} = identity, data_dir) do
    File.mkdir_p!(data_dir)
    path = identity_path(data_dir)

    data = %{
      trust_group_id: identity.trust_group_id,
      name: identity.name,
      public_key: Base.encode64(identity.public_key),
      private_key: Base.encode64(identity.private_key),
      algorithm: identity.algorithm,
      created_at: DateTime.to_iso8601(identity.created_at),
      provisional: identity.provisional
    }

    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        File.write!(path, json)
        # Set restrictive permissions (owner read/write only)
        File.chmod(path, 0o600)
        Logger.info("[TrustGroup] Saved identity to #{path}")
        :ok

      {:error, reason} ->
        Logger.error("[TrustGroup] Failed to encode identity: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_identity(data_dir) do
    path = identity_path(data_dir)

    with {:ok, json} <- File.read(path),
         {:ok, data} <- Jason.decode(json, keys: :atoms),
         {:ok, pub_key} <- Base.decode64(data.public_key) do

      # Determine if this is a key holder or member identity
      mode = data[:mode] || :key_holder

      identity = case mode do
        :key_holder ->
          case Base.decode64(data.private_key) do
            {:ok, priv_key} ->
              %__MODULE__{
                trust_group_id: data.trust_group_id,
                name: data.name,
                public_key: pub_key,
                private_key: priv_key,
                algorithm: data[:algorithm] || :ed25519,
                created_at: parse_datetime(data[:created_at]),
                mode: :key_holder,
                # Default to true for backwards compatibility with existing identity files
                provisional: Map.get(data, :provisional, true)
              }

            _ ->
              {:error, :missing_private_key}
          end

        :member ->
          %__MODULE__{
            trust_group_id: data.trust_group_id,
            name: data.name,
            public_key: pub_key,
            private_key: nil,
            algorithm: :ed25519,
            created_at: parse_datetime(data[:created_at]),
            mode: :member,
            node_name: data[:node_name],
            node_cert: data[:node_cert],
            # Members are not provisional - they joined an established trust group
            provisional: false
          }
      end

      case identity do
        {:error, _} = error ->
          error

        %__MODULE__{} = id ->
          # Verify the loaded identity is consistent
          if derive_trust_group_id(pub_key) == data.trust_group_id do
            {:ok, id}
          else
            Logger.warning("[TrustGroup] Identity file corrupted - trust_group_id mismatch")
            {:error, :corrupted}
          end
      end
    else
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions - Compressed IDs
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @doc """
  Derives a 4-byte compressed ID from a UUID string.

  Used for LoRa packets where full 16-byte UUIDs are too expensive.
  4 bytes = ~4 billion unique values, collision-safe for realistic deployments.

  ## Parameters
  - `uuid_string` - UUID in standard format (8-4-4-4-12)

  ## Returns
  - 4-byte binary compressed ID
  """
  @spec compressed_id(String.t()) :: binary()
  def compressed_id(uuid_string) when is_binary(uuid_string) do
    binary_part(:crypto.hash(:sha256, uuid_string), 0, 4)
  end

  @doc """
  Returns the compressed ID for this node's Trust Group.

  ## Returns
  - `{:ok, binary()}` - 4-byte compressed trust group ID
  - `{:error, :not_initialized}` - Identity not ready
  """
  @spec get_trust_group_compressed_id() :: {:ok, binary()} | {:error, :not_initialized}
  def get_trust_group_compressed_id do
    case get_trust_group_id() do
      {:ok, trust_group_id} -> {:ok, compressed_id(trust_group_id)}
      error -> error
    end
  end

  @doc """
  Formats a 4-byte compressed ID as a hex string for display.

  ## Parameters
  - `compressed` - 4-byte binary

  ## Returns
  - Hex string like "0xA3F7B2C1"
  """
  @spec compressed_id_to_hex(binary()) :: String.t()
  def compressed_id_to_hex(<<value::32>>) do
    "0x" <> String.upcase(Integer.to_string(value, 16) |> String.pad_leading(8, "0"))
  end
  def compressed_id_to_hex(_), do: "0x00000000"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Helpers
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp cert_to_signable(cert) do
    # Create deterministic string representation for signing
    cert
    |> Map.drop([:signature])
    |> Enum.sort()
    |> Enum.map(fn {k, v} -> "#{k}=#{format_value(v)}" end)
    |> Enum.join("|")
  end

  defp format_value(v) when is_list(v), do: Enum.join(v, ",")
  defp format_value(v) when is_atom(v), do: Atom.to_string(v)
  defp format_value(v), do: to_string(v)

  defp decode_signature(%{signature: sig}) when is_binary(sig) do
    Base.decode64(sig)
  end
  defp decode_signature(_), do: {:error, :no_signature}

  defp check_expiry(%{expires_at: :never}), do: {:ok, :never}
  defp check_expiry(%{expires_at: expires}) when is_integer(expires) do
    if System.system_time(:second) < expires do
      {:ok, expires}
    else
      {:error, :expired}
    end
  end
  defp check_expiry(_), do: {:error, :invalid_format}

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_datetime(_), do: DateTime.utc_now()

  # Generate a 4-character alphanumeric code (easy to type)
  defp generate_code do
    chars = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # No I, O, 0, 1 to avoid confusion
    1..4
    |> Enum.map(fn _ -> Enum.random(chars) end)
    |> List.to_string()
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Key Encryption
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @key_derivation_iterations 100_000

  defp encrypt_key_bundle(%__MODULE__{} = identity, passphrase) do
    # Derive encryption key from passphrase using PBKDF2
    salt = :crypto.strong_rand_bytes(16)
    key = derive_encryption_key(passphrase, salt)
    iv = :crypto.strong_rand_bytes(12)  # 12 bytes recommended for GCM

    # Prepare data to encrypt
    data = %{
      trust_group_id: identity.trust_group_id,
      name: identity.name,
      public_key: Base.encode64(identity.public_key),
      private_key: Base.encode64(identity.private_key),
      created_at: DateTime.to_iso8601(identity.created_at)
    }

    plaintext = Jason.encode!(data)

    # Encrypt with AES-256-GCM
    {ciphertext, tag} = :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      key,
      iv,
      plaintext,
      <<>>,  # AAD
      16,    # Tag length in bytes
      true   # encrypt
    )

    # Bundle: salt + iv + tag + ciphertext
    bundle = salt <> iv <> tag <> ciphertext
    {:ok, Base.encode64(bundle)}
  end

  defp decrypt_key_bundle(encrypted_data, passphrase) do
    with {:ok, bundle} <- Base.decode64(encrypted_data),
         <<salt::binary-16, iv::binary-12, tag::binary-16, ciphertext::binary>> <- bundle do

      key = derive_encryption_key(passphrase, salt)

      case :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key,
        iv,
        ciphertext,
        <<>>,  # AAD
        tag,
        false  # decrypt
      ) do
        plaintext when is_binary(plaintext) ->
          case Jason.decode(plaintext, keys: :atoms) do
            {:ok, data} ->
              {:ok, pub_key} = Base.decode64(data.public_key)
              {:ok, priv_key} = Base.decode64(data.private_key)

              {:ok, %__MODULE__{
                trust_group_id: data.trust_group_id,
                name: data.name,
                public_key: pub_key,
                private_key: priv_key,
                algorithm: :ed25519,
                created_at: parse_datetime(data[:created_at]),
                mode: :key_holder
              }}

            _ ->
              {:error, :invalid_format}
          end

        :error ->
          {:error, :invalid_passphrase}
      end
    else
      _ -> {:error, :invalid_format}
    end
  end

  defp derive_encryption_key(passphrase, salt) do
    # PBKDF2-SHA256 with high iteration count
    :crypto.pbkdf2_hmac(:sha256, passphrase, salt, @key_derivation_iterations, 32)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - Member Identity Persistence
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp save_member_identity(%__MODULE__{mode: :member} = identity, data_dir) do
    File.mkdir_p!(data_dir)
    path = identity_path(data_dir)

    data = %{
      trust_group_id: identity.trust_group_id,
      name: identity.name,
      public_key: Base.encode64(identity.public_key),
      mode: :member,
      node_name: identity.node_name,
      node_cert: identity.node_cert,
      created_at: DateTime.to_iso8601(identity.created_at)
    }

    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        File.write!(path, json)
        File.chmod(path, 0o600)
        Logger.info("[TrustGroup] Saved member identity to #{path}")
        :ok

      {:error, reason} ->
        Logger.error("[TrustGroup] Failed to encode member identity: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
