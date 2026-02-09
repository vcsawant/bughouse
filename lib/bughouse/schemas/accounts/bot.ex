defmodule Bughouse.Schemas.Accounts.Bot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bots" do
    belongs_to :player, Bughouse.Schemas.Accounts.Player

    # "internal" | "external"
    field :bot_type, :string
    # HTTP health endpoint (external bots only)
    field :health_url, :string
    # "online" | "offline" | "in_game"
    field :status, :string, default: "offline"
    # "single" | "dual" | "both"
    field :supported_modes, :string

    field :single_rating, :integer, default: 1200
    field :dual_rating, :integer, default: 1200

    # engine config passed to UBI
    field :config, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bot, attrs) do
    bot
    |> cast(attrs, [
      :player_id,
      :bot_type,
      :health_url,
      :status,
      :supported_modes,
      :single_rating,
      :dual_rating,
      :config
    ])
    |> validate_required([:player_id, :bot_type, :supported_modes])
    |> validate_inclusion(:bot_type, ["internal", "external"])
    |> validate_inclusion(:status, ["online", "offline", "in_game"])
    |> validate_inclusion(:supported_modes, ["single", "dual", "both"])
    |> unique_constraint(:player_id)
    |> foreign_key_constraint(:player_id)
    |> validate_health_url()
  end

  # External bots must declare a health endpoint so the lobby can verify
  # they're reachable before placing them in a game.
  defp validate_health_url(changeset) do
    bot_type = get_field(changeset, :bot_type)
    health_url = get_field(changeset, :health_url)

    if bot_type == "external" && is_nil(health_url) do
      add_error(changeset, :health_url, "is required for external bots")
    else
      changeset
    end
  end
end
