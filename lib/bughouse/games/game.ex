defmodule Bughouse.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "games" do
    field :invite_code, :string
    field :status, Ecto.Enum, values: [:waiting, :in_progress, :completed]

    # Player references
    field :board_1_white_id, :binary_id
    field :board_1_black_id, :binary_id
    field :board_2_white_id, :binary_id
    field :board_2_black_id, :binary_id

    field :time_control, :string
    field :moves, {:array, :map}
    field :result, :string
    field :result_details, :map
    field :result_timestamp, :utc_datetime_usec

    field :final_board_1_fen, :string
    field :final_board_2_fen, :string
    field :final_white_reserves, {:array, :string}
    field :final_black_reserves, {:array, :string}

    has_many :game_players, Bughouse.Games.GamePlayer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :invite_code,
      :status,
      :time_control,
      :board_1_white_id,
      :board_1_black_id,
      :board_2_white_id,
      :board_2_black_id,
      :moves,
      :result,
      :result_details,
      :result_timestamp,
      :final_board_1_fen,
      :final_board_2_fen,
      :final_white_reserves,
      :final_black_reserves
    ])
    |> validate_required([:invite_code, :status, :time_control])
    |> validate_inclusion(:status, [:waiting, :in_progress, :completed])
    |> unique_constraint(:invite_code)
  end
end
