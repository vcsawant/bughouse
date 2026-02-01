defmodule Bughouse.Schemas.Accounts.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_identities" do
    field :provider, :string
    field :uid, :string
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :integer
    field :user_data, :map

    belongs_to :player, Bughouse.Schemas.Accounts.Player

    timestamps(type: :utc_datetime)
  end

  def changeset(user_identity, attrs) do
    user_identity
    |> cast(attrs, [
      :provider,
      :uid,
      :player_id,
      :access_token,
      :refresh_token,
      :expires_at,
      :user_data
    ])
    |> validate_required([:provider, :uid, :player_id])
    |> unique_constraint([:provider, :uid])
  end
end
