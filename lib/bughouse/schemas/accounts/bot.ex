defmodule Bughouse.Schemas.Accounts.Bot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bots" do
    # The bot's game identity — a Player record with is_bot: true.
    # This is the ID used when the bot sits in a game seat.
    belongs_to :player, Bughouse.Schemas.Accounts.Player

    # The human who registered/manages this bot.
    belongs_to :owner, Bughouse.Schemas.Accounts.Player

    # Bot identity
    field :name, :string
    field :display_name, :string
    field :description, :string, default: ""

    # "internal" | "external"
    field :bot_type, :string

    # Connection (external bots)
    field :endpoint_base, :string

    # "online" | "offline" | "in_game"
    field :status, :string, default: "offline"

    # Engine settings
    field :config, :map, default: %{}
    field :default_options, :map, default: %{}
    field :max_concurrent_games, :integer, default: 1
    field :timeout_seconds, :integer, default: 10

    # Visibility
    field :is_public, :boolean, default: false
    field :is_active, :boolean, default: true

    # Stats
    field :games_played, :integer, default: 0
    field :games_won, :integer, default: 0
    field :current_rating, :integer, default: 1200

    # Health monitoring
    field :health_status, :string, default: "unknown"
    field :last_health_check, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bot, attrs) do
    bot
    |> cast(attrs, [
      :player_id,
      :owner_id,
      :name,
      :display_name,
      :description,
      :bot_type,
      :endpoint_base,
      :status,
      :config,
      :default_options,
      :max_concurrent_games,
      :timeout_seconds,
      :is_public,
      :is_active
    ])
    |> validate_required([:name, :display_name, :bot_type])
    |> validate_name()
    |> validate_inclusion(:bot_type, ["internal", "external"])
    |> validate_inclusion(:status, ["online", "offline", "in_game"])
    |> validate_number(:max_concurrent_games,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 5
    )
    |> validate_number(:timeout_seconds,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 60
    )
    |> unique_constraint(:name)
    |> foreign_key_constraint(:player_id)
    |> validate_endpoint_base()
  end

  @doc """
  Changeset for updating game stats (games_played, games_won).
  """
  def stats_changeset(bot, attrs) do
    bot
    |> cast(attrs, [:games_played, :games_won, :current_rating])
    |> validate_number(:games_played, greater_than_or_equal_to: 0)
    |> validate_number(:games_won, greater_than_or_equal_to: 0)
    |> validate_number(:current_rating, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for updating health/operational status.
  """
  def status_changeset(bot, attrs) do
    bot
    |> cast(attrs, [:status, :health_status, :last_health_check])
    |> validate_inclusion(:status, ["online", "offline", "in_game"])
  end

  defp validate_name(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-zA-Z0-9_]{3,20}$/,
      message: "must be 3-20 characters and contain only letters, numbers, and underscores"
    )
  end

  # External bots must declare an endpoint_base so the system can connect to them.
  defp validate_endpoint_base(changeset) do
    bot_type = get_field(changeset, :bot_type)
    endpoint_base = get_field(changeset, :endpoint_base)

    if bot_type == "external" && (is_nil(endpoint_base) || endpoint_base == "") do
      add_error(changeset, :endpoint_base, "is required for external bots")
    else
      changeset
    end
  end
end
