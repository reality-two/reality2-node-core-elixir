defmodule Reality2.Bootstrap do
  # *******************************************************************************************************************************************
  @moduledoc false
  # Check whether this is the first time this node has run, and give it a unique ID and set up the initial state.
  #
  # TODO: Make this more robust and secure.  Presently, it uses a simple file-based approach which is not suitable for production environments.
  #
  # **Author**
  # - Dr. Roy C. Davies
  # - [roycdavies.github.io](https://roycdavies.github.io/)
  # *******************************************************************************************************************************************
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def put(key, value), do: GenServer.call(__MODULE__, {:put, key, value})
  def get(key, default \\ nil), do: GenServer.call(__MODULE__, {:get, key, default})

  @impl true
  def init(state) do
    node_id = ensure_node_id!()
    {:ok, Map.put(state, :node_id, node_id)}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state),
    do: {:reply, :ok, Map.put(state, key, value)}

  def handle_call({:get, key, default}, _from, state),
    do: {:reply, Map.get(state, key, default), state}

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  @spec ensure_node_id!() :: String.t()
  defp ensure_node_id! do
    path = Path.join(File.cwd!(), ".node")

    case File.read(path) do
      {:ok, contents} ->
        String.trim(contents)

      {:error, :enoent} ->
        id = UUID.uuid4()
        tmp = path <> ".tmp"

        File.write!(tmp, id <> "\n")
        File.rename!(tmp, path)

        # Optional: restrict permissions (may fail on some platforms/FS)
        _ =
          try do
            File.chmod!(path, 0o600)
          rescue
            _ -> :ok
          end

        id

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read", path: path
    end
  end
end
