defmodule Bughouse.Repo.Migrations.AddBotSupport do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :is_bot, :boolean, default: false
    end

    create table(:bots, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :player_id, references(:players, type: :uuid), null: false

      # "internal" | "external"
      add :bot_type, :string, null: false
      # required for external bots only
      add :health_url, :string
      # "online" | "offline" | "in_game"
      add :status, :string, default: "offline"
      # "single" | "dual" | "both"
      add :supported_modes, :string, null: false

      add :single_rating, :integer, default: 1200
      add :dual_rating, :integer, default: 1200

      # engine config: depth, time_limit, etc.
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bots, [:player_id])
    create index(:bots, [:status])
  end
end
