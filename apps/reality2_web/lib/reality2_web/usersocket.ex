defmodule Reality2Web.UserSocket do
  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: Reality2Web.Schema

  @impl true
  def connect(query_params, socket, _connect_info) do
    case authorize_user(socket, query_params) do
      {:ok, user} ->
        {:ok, Absinthe.Phoenix.Socket.put_options(socket, context: %{current_user: user})}
        # {:error, _reason} ->
        #   # Reject the connection
        #   :error
    end
  end

  defp authorize_user(_socket, _query_params) do
    # TODO: Implement proper authentication here.
    # Consider proximity-based auth (BLE challenge, WiFi hotspot association),
    # token-based auth (signed JWT from a trusted app), or device pairing.
    # Currently accepts all connections — acceptable only if the node is
    # access-controlled at the network level (e.g., private WiFi hotspot).
    {:ok, :anonymous}
  end

  @impl true
  def id(_socket) do
    nil
  end
end
