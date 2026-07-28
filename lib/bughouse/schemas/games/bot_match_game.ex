defmodule Bughouse.Schemas.Games.BotMatchGame do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bot_match_games" do
    belongs_to :bot_match, Bughouse.Schemas.Games.BotMatch
    belongs_to :game, Bughouse.Schemas.Games.Game
    field :game_number, :integer
    field :result, :string
    field :bot_a_team, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(match_game, attrs) do
    match_game
    |> cast(attrs, [:bot_match_id, :game_id, :game_number, :result, :bot_a_team])
    |> validate_required([:bot_match_id, :game_id, :game_number, :bot_a_team])
    |> validate_inclusion(:result, ["bot_a_win", "bot_b_win", "draw"])
    |> validate_inclusion(:bot_a_team, ["team_1", "team_2"])
    |> foreign_key_constraint(:bot_match_id)
    |> foreign_key_constraint(:game_id)
  end
end
