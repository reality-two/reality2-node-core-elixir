defmodule Reality2Web.Reality2Controller do
  @moduledoc false

  use Reality2Web, :controller

  @sites_dir "priv/static/sites"

  def index(conn, params) do
    site = Map.get(params, "site", "sentants")

    # Reject path traversal attempts — only allow simple alphanumeric names with hyphens/underscores
    if Regex.match?(~r/\A[a-zA-Z0-9_-]+\z/, site) do
      index_path = Path.join([Application.app_dir(:reality2_web), @sites_dir, site, "index.html"])

      if File.exists?(index_path) do
        html(conn, File.read!(index_path))
      else
        conn
        |> put_status(:not_found)
        |> text("Site not found")
      end
    else
      conn
      |> put_status(:bad_request)
      |> text("Invalid site name")
    end
  end
end
