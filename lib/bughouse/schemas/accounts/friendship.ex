defmodule Bughouse.Schemas.Accounts.Friendship do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "friendships" do
    belongs_to :player, Bughouse.Schemas.Accounts.Player
    belongs_to :friend, Bughouse.Schemas.Accounts.Player

    field :status, Ecto.Enum, values: [:pending, :accepted, :blocked]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:player_id, :friend_id, :status])
    |> validate_required([:player_id, :friend_id])
    |> unique_constraint([:player_id, :friend_id])
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:friend_id)
  end
end
