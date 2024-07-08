defmodule Reality2Web.Reality2Controller do
@moduledoc false

use Reality2Web, :controller

  def index(conn, _params) do

    [path] = case Map.get(conn, :path_info) do
      [] -> ["sentants"]
      path_info -> path_info
    end

    html(conn, File.read!( Application.app_dir(:reality2_web) <> "/priv/static/sites/" <> path <> "/index.html"))
  end
end
