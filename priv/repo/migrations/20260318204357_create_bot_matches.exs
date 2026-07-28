defmodule Bughouse.Repo.Migrations.CreateBotMatches do
  use Ecto.Migration

  def change do
    create table(:bot_matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :bot_a_id, references(:bots, type: :binary_id), null: false
      add :bot_b_id, references(:bots, type: :binary_id), null: false
      add :total_games, :integer, null: false
      add :completed_games, :integer, null: false, default: 0
      add :time_control_ms, :integer, null: false
      add :bot_a_wins, :integer, null: false, default: 0
      add :bot_b_wins, :integer, null: false, default: 0
      add :draws, :integer, null: false, default: 0
      add :current_game_id, references(:games, type: :binary_id), null: true
      add :created_by_id, references(:players, type: :binary_id), null: false
      add :started_at, :utc_datetime, null: true
      add :completed_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:bot_matches, [:created_by_id])
    create index(:bot_matches, [:status])

    create table(:bot_match_games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bot_match_id, references(:bot_matches, type: :binary_id, on_delete: :delete_all),
        null: false
      add :game_id, references(:games, type: :binary_id), null: false
      add :game_number, :integer, null: false
      add :result, :string, null: true
      add :bot_a_team, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:bot_match_games, [:bot_match_id])

    # Add match_metadata to games for engine metadata passthrough
    alter table(:games) do
      add :match_metadata, :map, null: true
    end
  end
end
