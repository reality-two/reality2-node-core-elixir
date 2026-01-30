defmodule Reality2Web.Plugs.QueryDepthLimit do
  @moduledoc false
  # Plug that rejects GraphQL queries exceeding a maximum brace-nesting depth.
  # This is a lightweight pre-parse check to block obviously abusive queries.

  @behaviour Plug
  @max_depth 10

  def init(opts), do: Keyword.get(opts, :max_depth, @max_depth)

  def call(conn, max_depth) do
    case get_query(conn) do
      nil ->
        conn

      query ->
        if brace_depth(query) > max_depth do
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(400, Jason.encode!(%{errors: [%{message: "Query exceeds maximum nesting depth of #{max_depth}"}]}))
          |> Plug.Conn.halt()
        else
          conn
        end
    end
  end

  defp get_query(conn) do
    case conn.body_params do
      %{"query" => query} when is_binary(query) -> query
      _ -> nil
    end
  end

  defp brace_depth(str) do
    str
    |> String.graphemes()
    |> Enum.reduce({0, 0}, fn char, {current, max_seen} ->
      case char do
        "{" -> {current + 1, max(max_seen, current + 1)}
        "}" -> {max(current - 1, 0), max_seen}
        _ -> {current, max_seen}
      end
    end)
    |> elem(1)
  end
end
