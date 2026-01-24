defmodule Bughouse.Repo.Migrations.CreateGamePlayers do
  use Ecto.Migration

  def change do
    create table(:game_players, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :game_id, references(:games, type: :uuid, on_delete: :delete_all), null: false
      add :player_id, references(:players, type: :uuid, on_delete: :delete_all), null: false

      # Position in game
      # "board_1_white", "board_1_black", etc.
      add :position, :string, null: false
      # "white" or "black"
      add :color, :string, null: false
      # 1 or 2
      add :board, :integer, null: false

      # Ratings at time of game
      add :rating_before, :integer, null: false
      add :rating_after, :integer
      add :rating_change, :integer

      # Outcome for this player
      add :won, :boolean
      # "win", "loss", "draw", "incomplete"
      add :outcome, :string

      timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
    end

    create index(:game_players, [:game_id])
    create index(:game_players, [:player_id])
    create index(:game_players, [:player_id, :won])
    create index(:game_players, [:player_id, :color])
    create index(:game_players, [:player_id, :outcome])
    create index(:game_players, [:rating_before])
  end
end
