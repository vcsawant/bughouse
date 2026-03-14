defmodule Bughouse.Repo.Migrations.AddOwnerIdToBots do
  use Ecto.Migration

  def change do
    alter table(:bots) do
      add :owner_id, references(:players, type: :uuid), null: true
    end

    create index(:bots, [:owner_id])

    # Backfill: for existing bots (like Rusty), owner_id = player_id
    # (the bot's player identity is also its owner for legacy bots)
    execute "UPDATE bots SET owner_id = player_id", ""
  end
end
