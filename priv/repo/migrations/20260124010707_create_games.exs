defmodule Bughouse.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :invite_code, :string, null: false
      add :status, :string, default: "waiting", null: false

      # Player positions (denormalized for convenience)
      add :board_1_white_id, references(:players, type: :uuid, on_delete: :nilify_all)
      add :board_1_black_id, references(:players, type: :uuid, on_delete: :nilify_all)
      add :board_2_white_id, references(:players, type: :uuid, on_delete: :nilify_all)
      add :board_2_black_id, references(:players, type: :uuid, on_delete: :nilify_all)

      # Time control (e.g., "10min", "15min", "3+2")
      add :time_control, :string, null: false

      # Move history (JSONB array - written at game end)
      # Structure: [%{player: 1, move_time: 2.345, notation: "e2e4", board: 1}, ...]
      add :moves, :jsonb, default: "[]"

      # Game result
      add :result, :string  # "timeout", "king_captured", "draw", "incomplete"
      add :result_details, :jsonb  # Who timed out, which king captured, etc.
      add :result_timestamp, :utc_datetime_usec

      # Final board states (for analytics/visualization)
      add :final_board_1_fen, :text
      add :final_board_2_fen, :text
      add :final_white_reserves, {:array, :string}, default: []
      add :final_black_reserves, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:games, [:invite_code])
    create index(:games, [:status])
    create index(:games, [:time_control])
    create index(:games, [:result])
    create index(:games, [:inserted_at])
    create index(:games, [:result_timestamp])
  end
end
