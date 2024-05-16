defmodule Reality2Web.Reality2Controller do
@moduledoc false

  use Reality2Web, :controller

  def index(conn, _params) do
    html(conn, File.read!( Application.app_dir(:reality2_web) <> "/priv/static/sentants/index.html"))
  end
end
