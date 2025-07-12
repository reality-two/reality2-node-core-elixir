defmodule Reality2Web.Plugs.SetLocalContext do
  @behaviour Plug
  def init(opts), do: opts

  def call(conn, _opts) do
    remote_ip = Tuple.to_list(conn.remote_ip) |> Enum.join(".")
    is_local = remote_ip in ["127.0.0.1", "::1", "localhost"]

    Absinthe.Plug.put_options(conn, context: %{local?: is_local})
  end
end
