defmodule Bughouse.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :player_id, references(:players, type: :uuid, on_delete: :delete_all), null: false
      add :friend_id, references(:players, type: :uuid, on_delete: :delete_all), null: false
      add :status, :string, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:friendships, [:player_id])
    create index(:friendships, [:friend_id])
    create unique_index(:friendships, [:player_id, :friend_id])
  end
end
