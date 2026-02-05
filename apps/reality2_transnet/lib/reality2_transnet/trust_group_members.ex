defmodule Reality2Transnet.TrustGroupMembers do
  @moduledoc """
  Persistent storage for approved trust group members.

  Stores both node members (Reality2 nodes) and viewer members (phones, tablets,
  or other devices that can view but not host sentants).

  ## Member Types

  - `:node` — Full Reality2 node that can host sentants and participate in mesh
  - `:viewer` — Device that can view/interact with sentants but doesn't host them

  ## Persistence

  Members are persisted to `trust_group_data/members.json` and reloaded on boot.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  use GenServer
  require Logger

  @members_filename "members.json"

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Types
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @typedoc "Member type — node or viewer device"
  @type member_type :: :node | :viewer

  @typedoc "A trust group member entry"
  @type member :: %{
    node_id: String.t(),
    node_name: String.t(),
    node_public_key: String.t(),
    certificate: String.t() | nil,
    approved_at: String.t(),
    member_type: member_type()
  }

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Client API
  # -----------------------------------------------------------------------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add a new approved member to the trust group.

  ## Parameters

  - `node_id` — Unique identifier (typically a UUID or public key fingerprint)
  - `node_name` — Human-readable name
  - `node_public_key` — Ed25519 public key in base64 or hex
  - `certificate` — Membership certificate (optional, can be nil)
  - `member_type` — `:node` for full nodes, `:viewer` for viewer devices

  ## Returns

  - `{:ok, member}` — The created member entry
  - `{:error, :already_exists}` — Member with this node_id already exists
  """
  @spec add_member(String.t(), String.t(), String.t(), String.t() | nil, member_type()) ::
          {:ok, member()} | {:error, :already_exists}
  def add_member(node_id, node_name, node_public_key, certificate, member_type)
      when member_type in [:node, :viewer] do
    GenServer.call(__MODULE__, {:add_member, node_id, node_name, node_public_key, certificate, member_type})
  end

  @doc """
  Remove a member from the trust group.

  ## Parameters

  - `node_id` — The ID of the member to remove

  ## Returns

  - `:ok` — Member was removed (or didn't exist)
  """
  @spec remove_member(String.t()) :: :ok
  def remove_member(node_id) do
    GenServer.call(__MODULE__, {:remove_member, node_id})
  end

  @doc """
  List all approved trust group members.

  ## Returns

  A list of all member entries, sorted by approved_at timestamp.
  """
  @spec list_members() :: [member()]
  def list_members do
    GenServer.call(__MODULE__, :list_members)
  end

  @doc """
  Get a specific member by node_id.

  ## Returns

  - `{:ok, member}` — The member entry
  - `{:error, :not_found}` — No member with that ID
  """
  @spec get_member(String.t()) :: {:ok, member()} | {:error, :not_found}
  def get_member(node_id) do
    GenServer.call(__MODULE__, {:get_member, node_id})
  end

  @doc """
  Check if a node_id is an approved member.
  """
  @spec member?(String.t()) :: boolean()
  def member?(node_id) do
    GenServer.call(__MODULE__, {:member?, node_id})
  end

  @doc """
  List members filtered by type.

  ## Parameters

  - `member_type` — `:node` or `:viewer`
  """
  @spec list_by_type(member_type()) :: [member()]
  def list_by_type(member_type) when member_type in [:node, :viewer] do
    GenServer.call(__MODULE__, {:list_by_type, member_type})
  end

  @doc """
  Force persist members to disk.
  """
  @spec persist() :: :ok
  def persist do
    GenServer.call(__MODULE__, :persist)
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    data_dir = get_data_dir()

    state = case load_members(data_dir) do
      {:ok, members} ->
        Logger.info("[TrustGroupMembers] Loaded #{map_size(members)} approved members")
        members

      {:error, :not_found} ->
        Logger.info("[TrustGroupMembers] No existing members file, starting fresh")
        %{}

      {:error, reason} ->
        Logger.warning("[TrustGroupMembers] Failed to load members: #{inspect(reason)}, starting fresh")
        %{}
    end

    {:ok, %{members: state, data_dir: data_dir, dirty: false}}
  end

  @impl true
  def handle_call({:add_member, node_id, node_name, node_public_key, certificate, member_type}, _from, state) do
    if Map.has_key?(state.members, node_id) do
      {:reply, {:error, :already_exists}, state}
    else
      member = %{
        node_id: node_id,
        node_name: node_name,
        node_public_key: node_public_key,
        certificate: certificate,
        approved_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        member_type: member_type
      }

      new_members = Map.put(state.members, node_id, member)
      new_state = %{state | members: new_members, dirty: true}

      # Persist immediately on member changes for durability
      persist_members(new_members, state.data_dir)

      Logger.info("[TrustGroupMembers] Added #{member_type} member: #{node_name} (#{truncate_id(node_id)})")
      {:reply, {:ok, member}, %{new_state | dirty: false}}
    end
  end

  @impl true
  def handle_call({:remove_member, node_id}, _from, state) do
    case Map.get(state.members, node_id) do
      nil ->
        {:reply, :ok, state}

      member ->
        new_members = Map.delete(state.members, node_id)
        new_state = %{state | members: new_members, dirty: true}

        # Persist immediately on member changes
        persist_members(new_members, state.data_dir)

        Logger.info("[TrustGroupMembers] Removed member: #{member.node_name} (#{truncate_id(node_id)})")
        {:reply, :ok, %{new_state | dirty: false}}
    end
  end

  @impl true
  def handle_call(:list_members, _from, state) do
    members = state.members
    |> Map.values()
    |> Enum.sort_by(& &1.approved_at)

    {:reply, members, state}
  end

  @impl true
  def handle_call({:get_member, node_id}, _from, state) do
    case Map.get(state.members, node_id) do
      nil -> {:reply, {:error, :not_found}, state}
      member -> {:reply, {:ok, member}, state}
    end
  end

  @impl true
  def handle_call({:member?, node_id}, _from, state) do
    {:reply, Map.has_key?(state.members, node_id), state}
  end

  @impl true
  def handle_call({:list_by_type, member_type}, _from, state) do
    members = state.members
    |> Map.values()
    |> Enum.filter(& &1.member_type == member_type)
    |> Enum.sort_by(& &1.approved_at)

    {:reply, members, state}
  end

  @impl true
  def handle_call(:persist, _from, state) do
    persist_members(state.members, state.data_dir)
    {:reply, :ok, %{state | dirty: false}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.dirty do
      persist_members(state.members, state.data_dir)
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private — Persistence
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp get_data_dir do
    Application.get_env(:reality2_transnet, :trust_group_data_dir, ".r2")
    |> Path.join("trust_group_data")
  end

  defp members_path(data_dir) do
    Path.join(data_dir, @members_filename)
  end

  defp persist_members(members, data_dir) do
    File.mkdir_p!(data_dir)
    path = members_path(data_dir)

    export = %{
      members: Map.values(members) |> Enum.map(&export_member/1),
      persisted_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Jason.encode(export, pretty: true) do
      {:ok, json} ->
        File.write!(path, json)
        File.chmod(path, 0o600)
        Logger.debug("[TrustGroupMembers] Persisted #{map_size(members)} members to #{path}")

      {:error, reason} ->
        Logger.error("[TrustGroupMembers] Failed to encode members: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.error("[TrustGroupMembers] Failed to persist: #{inspect(e)}")
  end

  defp export_member(member) do
    %{
      node_id: member.node_id,
      node_name: member.node_name,
      node_public_key: member.node_public_key,
      certificate: member.certificate,
      approved_at: member.approved_at,
      member_type: to_string(member.member_type)
    }
  end

  defp load_members(data_dir) do
    path = members_path(data_dir)

    with {:ok, json} <- File.read(path),
         {:ok, data} <- Jason.decode(json, keys: :atoms) do

      members = data
      |> Map.get(:members, [])
      |> Enum.map(&import_member/1)
      |> Map.new(fn m -> {m.node_id, m} end)

      {:ok, members}
    else
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  defp import_member(data) do
    %{
      node_id: Map.get(data, :node_id),
      node_name: Map.get(data, :node_name, "Unknown"),
      node_public_key: Map.get(data, :node_public_key),
      certificate: Map.get(data, :certificate),
      approved_at: Map.get(data, :approved_at),
      member_type: import_member_type(Map.get(data, :member_type, "node"))
    }
  end

  defp import_member_type("node"), do: :node
  defp import_member_type("viewer"), do: :viewer
  defp import_member_type(:node), do: :node
  defp import_member_type(:viewer), do: :viewer
  defp import_member_type(_), do: :node

  defp truncate_id(id) when is_binary(id) and byte_size(id) > 12 do
    String.slice(id, 0, 8) <> "..."
  end
  defp truncate_id(id), do: id
end
