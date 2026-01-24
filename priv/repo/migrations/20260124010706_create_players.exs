defmodule Bughouse.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :display_name, :string, null: false
      add :current_rating, :integer, default: 1200
      add :peak_rating, :integer, default: 1200
      add :total_games, :integer, default: 0
      add :wins, :integer, default: 0
      add :losses, :integer, default: 0
      add :draws, :integer, default: 0

      # Guest vs registered user support
      add :guest, :boolean, default: true
      add :email, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:players, [:display_name])
    create index(:players, [:current_rating])
    create index(:players, [:guest])
  end
end
