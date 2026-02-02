defmodule AiReality2Transnet.JoinRequests do
  @moduledoc """
  Ephemeral storage for pending hive join requests.
  Requests expire after 10 minutes.

  Part of the hive join protocol alongside HiveIdentity and HiveJoinBle.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  @stale_seconds 600
  @max_pending_per_source 3
  @max_pending_total 10

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc "Submit a new join request. Returns the request or {:error, :rate_limited}."
  def submit(node_name, node_public_key) do
    id = generate_id()
    now = System.system_time(:second)

    request = %{
      id: id,
      node_name: node_name,
      node_public_key: node_public_key,
      status: :pending,
      submitted_at: now,
      certificate: nil,
      hive_public_info: nil
    }

    Agent.get_and_update(__MODULE__, fn state ->
      cleaned = cleanup_stale(state, now)

      # Rate limit: max pending per source (node_public_key)
      source_pending = Enum.count(cleaned, fn {_id, req} ->
        req.status == :pending and req.node_public_key == node_public_key
      end)

      # Rate limit: max total pending
      total_pending = Enum.count(cleaned, fn {_id, req} -> req.status == :pending end)

      cond do
        source_pending >= @max_pending_per_source ->
          {{:error, :rate_limited}, cleaned}

        total_pending >= @max_pending_total ->
          {{:error, :rate_limited}, cleaned}

        true ->
          {request, Map.put(cleaned, id, request)}
      end
    end)
  end

  @doc "List all pending requests."
  def list_pending do
    now = System.system_time(:second)

    Agent.get(__MODULE__, fn state ->
      state
      |> Enum.filter(fn {_id, req} ->
        req.status == :pending and (now - req.submitted_at) < @stale_seconds
      end)
      |> Enum.map(fn {_id, req} -> req end)
      |> Enum.sort_by(& &1.submitted_at)
    end)
  end

  @doc "Get a request by ID (for status polling)."
  def get_status(id) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state, id) do
        nil -> :not_found
        req -> {:ok, req}
      end
    end)
  end

  @doc "Mark a request as approved and store the certificate + hive info."
  def set_result(id, certificate, hive_public_info) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state, id) do
        nil ->
          {:not_found, state}

        req ->
          updated = %{req | status: :approved, certificate: certificate, hive_public_info: hive_public_info}
          {{:ok, updated}, Map.put(state, id, updated)}
      end
    end)
  end

  @doc "Deny and remove a request."
  def deny(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state, id) do
        nil ->
          {:not_found, state}

        req ->
          denied = %{req | status: :denied}
          {{:ok, denied}, Map.put(state, id, denied)}
      end
    end)
  end

  @doc "Remove a request (after joiner has consumed it)."
  def remove(id) do
    Agent.update(__MODULE__, &Map.delete(&1, id))
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp cleanup_stale(state, now) do
    Map.reject(state, fn {_id, req} ->
      (now - req.submitted_at) >= @stale_seconds
    end)
  end
end
