defmodule Reality2.Repo.Migrations.CreateSentant do
  use Ecto.Migration

  def change do
    create table(:sentant, primary_key: false) do
      add :uuid, :uuid, primary_key: true
      add :name, :string
      add :data, :json
      add :automations, :json

      # timestamps()
    end
  end
end
