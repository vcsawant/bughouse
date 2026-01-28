defmodule Bughouse.Schemas.Games.GamePlayer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_players" do
    belongs_to :game, Bughouse.Schemas.Games.Game
    belongs_to :player, Bughouse.Schemas.Accounts.Player

    field :position, :string
    field :color, :string
    field :board, :integer
    field :rating_before, :integer
    field :rating_after, :integer
    field :rating_change, :integer
    field :won, :boolean
    field :outcome, Ecto.Enum, values: [:win, :loss, :draw, :incomplete]

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  @doc false
  def changeset(game_player, attrs) do
    game_player
    |> cast(attrs, [
      :game_id,
      :player_id,
      :position,
      :color,
      :board,
      :rating_before,
      :rating_after,
      :rating_change,
      :won,
      :outcome
    ])
    |> validate_required([
      :game_id,
      :player_id,
      :position,
      :color,
      :board,
      :rating_before,
      :outcome
    ])
    |> validate_inclusion(:color, ["white", "black"])
    |> validate_inclusion(:board, [1, 2])
    |> foreign_key_constraint(:game_id)
    |> foreign_key_constraint(:player_id)
  end
end
