defmodule Bughouse.Accounts.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :display_name, :string
    field :current_rating, :integer
    field :peak_rating, :integer
    field :total_games, :integer
    field :wins, :integer
    field :losses, :integer
    field :draws, :integer
    field :guest, :boolean
    field :email, :string

    has_many :game_players, Bughouse.Games.GamePlayer
    has_many :games, through: [:game_players, :game]
    has_many :friendships, Bughouse.Accounts.Friendship

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(player, attrs) do
    player
    |> cast(attrs, [
      :display_name, :current_rating, :peak_rating,
      :total_games, :wins, :losses, :draws, :guest, :email
    ])
    |> validate_required([:display_name])
    |> unique_constraint(:display_name)
    |> validate_number(:current_rating, greater_than_or_equal_to: 0)
  end
end
