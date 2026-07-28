defmodule Bughouse.Schemas.Games.BotMatch do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bot_matches" do
    field :status, :string, default: "pending"
    belongs_to :bot_a, Bughouse.Schemas.Accounts.Bot
    belongs_to :bot_b, Bughouse.Schemas.Accounts.Bot
    field :total_games, :integer
    field :completed_games, :integer, default: 0
    field :time_control_ms, :integer
    field :parallel_games, :integer, default: 1
    field :bot_a_wins, :integer, default: 0
    field :bot_b_wins, :integer, default: 0
    field :draws, :integer, default: 0
    belongs_to :current_game, Bughouse.Schemas.Games.Game
    belongs_to :created_by, Bughouse.Schemas.Accounts.Player
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    has_many :bot_match_games, Bughouse.Schemas.Games.BotMatchGame

    timestamps(type: :utc_datetime)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [
      :status,
      :bot_a_id,
      :bot_b_id,
      :total_games,
      :completed_games,
      :time_control_ms,
      :parallel_games,
      :bot_a_wins,
      :bot_b_wins,
      :draws,
      :current_game_id,
      :created_by_id,
      :started_at,
      :completed_at
    ])
    |> validate_required([:bot_a_id, :bot_b_id, :total_games, :time_control_ms, :created_by_id])
    |> validate_inclusion(:status, ["pending", "running", "completed", "cancelled"])
    |> validate_number(:total_games, greater_than: 0, less_than_or_equal_to: 1000)
    |> validate_number(:time_control_ms, greater_than: 0)
    |> validate_number(:parallel_games, greater_than: 0, less_than_or_equal_to: 10)
    |> foreign_key_constraint(:bot_a_id)
    |> foreign_key_constraint(:bot_b_id)
    |> foreign_key_constraint(:created_by_id)
  end
end
