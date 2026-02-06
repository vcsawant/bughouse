defmodule Bughouse.Schemas.Accounts.Player do
  use Ecto.Schema
  import Ecto.Changeset

  alias Bughouse.Schemas.Accounts.UserIdentity

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :username, :string
    field :display_name, :string
    field :current_rating, :integer
    field :peak_rating, :integer
    field :total_games, :integer
    field :wins, :integer
    field :losses, :integer
    field :draws, :integer
    field :guest, :boolean
    field :is_bot, :boolean, default: false
    field :email, :string
    field :email_confirmed_at, :utc_datetime

    has_one :bot, Bughouse.Schemas.Accounts.Bot
    has_many :game_players, Bughouse.Schemas.Games.GamePlayer
    has_many :games, through: [:game_players, :game]
    has_many :friendships, Bughouse.Schemas.Accounts.Friendship
    has_many :user_identities, UserIdentity

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(player, attrs) do
    player
    |> cast(attrs, [
      :username,
      :display_name,
      :current_rating,
      :peak_rating,
      :total_games,
      :wins,
      :losses,
      :draws,
      :guest,
      :is_bot,
      :email,
      :email_confirmed_at
    ])
    |> validate_required([:display_name])
    |> validate_username()
    |> unique_constraint(:username, name: :players_username_index)
    |> unique_constraint(:email, name: :players_email_index)
    |> validate_number(:current_rating, greater_than_or_equal_to: 0)
  end

  defp validate_username(changeset) do
    changeset
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]{3,20}$/,
      message: "must be 3-20 characters and contain only letters, numbers, and underscores"
    )
  end
end
