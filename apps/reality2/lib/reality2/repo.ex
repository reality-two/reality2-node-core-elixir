defmodule Reality2.Repo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :reality2,
    adapter: Ecto.Adapters.Postgres
end
