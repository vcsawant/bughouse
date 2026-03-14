defmodule Bughouse.Repo.Migrations.ExtendBotsTable do
  use Ecto.Migration

  def change do
    # Drop the unique constraint on player_id (allow multiple bots per user)
    drop unique_index(:bots, [:player_id])
    create index(:bots, [:player_id])

    alter table(:bots) do
      # Remove old columns
      remove :health_url, :string
      remove :supported_modes, :string
      remove :single_rating, :integer, default: 1200
      remove :dual_rating, :integer, default: 1200

      # Bot identity
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :description, :text, default: ""

      # Connection (external bots)
      add :endpoint_base, :string

      # Engine settings
      add :max_concurrent_games, :integer, default: 1
      add :timeout_seconds, :integer, default: 10
      add :default_options, :map, default: %{}

      # Visibility & status
      add :is_public, :boolean, default: false
      add :is_active, :boolean, default: true

      # Stats
      add :games_played, :integer, default: 0
      add :games_won, :integer, default: 0
      add :current_rating, :integer, default: 1200

      # Health monitoring
      add :health_status, :string, default: "unknown"
      add :last_health_check, :utc_datetime
    end

    create unique_index(:bots, [:name])
    create index(:bots, [:is_active])
    create index(:bots, [:is_public, :is_active])
  end
end
