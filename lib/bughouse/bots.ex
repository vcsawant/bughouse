defmodule Bughouse.Bots do
  @moduledoc """
  The Bots context — bot registration, management, and stats.
  """

  import Ecto.Query, warn: false
  alias Bughouse.Repo
  alias Bughouse.Schemas.Accounts.Bot

  @doc """
  Creates a new bot.
  """
  def create_bot(attrs) do
    %Bot{}
    |> Bot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a bot by ID. Raises if not found.
  """
  def get_bot!(id), do: Repo.get!(Bot, id)

  @doc """
  Gets a bot by ID. Returns nil if not found.
  """
  def get_bot(id), do: Repo.get(Bot, id)

  @doc """
  Gets a bot by its unique name.
  """
  def get_bot_by_name(name) do
    Repo.get_by(Bot, name: name)
  end

  @doc """
  Updates a bot.
  """
  def update_bot(%Bot{} = bot, attrs) do
    bot
    |> Bot.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bot.
  """
  def delete_bot(%Bot{} = bot) do
    Repo.delete(bot)
  end

  @doc """
  Returns a changeset for tracking bot changes (used by LiveView forms).
  """
  def change_bot(%Bot{} = bot, attrs \\ %{}) do
    Bot.changeset(bot, attrs)
  end

  @doc """
  Lists all bots owned by a player, ordered by name.
  """
  def list_bots_for_owner(player_id) do
    from(b in Bot,
      where: b.player_id == ^player_id,
      order_by: [asc: b.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists all public, active bots with their player preloaded, ordered by rating desc.
  """
  def list_public_bots do
    from(b in Bot,
      where: b.is_public == true and b.is_active == true,
      preload: :player,
      order_by: [desc: b.current_rating]
    )
    |> Repo.all()
  end

  @doc """
  Checks if a bot name is available.
  """
  def name_available?(name) do
    !Repo.exists?(from(b in Bot, where: b.name == ^name))
  end

  @doc """
  Records a game result for a bot, incrementing stats.
  """
  def record_game_result(%Bot{} = bot, outcome) do
    attrs =
      case outcome do
        :win ->
          %{games_played: bot.games_played + 1, games_won: bot.games_won + 1}

        :loss ->
          %{games_played: bot.games_played + 1}

        :draw ->
          %{games_played: bot.games_played + 1}
      end

    bot
    |> Bot.stats_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the health status and last check timestamp of a bot.
  """
  def update_health_status(%Bot{} = bot, status_string) do
    bot
    |> Bot.status_changeset(%{
      health_status: status_string,
      last_health_check: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Updates the operational status (online/offline/in_game) of a bot.
  """
  def update_status(%Bot{} = bot, status_string) do
    bot
    |> Bot.status_changeset(%{status: status_string})
    |> Repo.update()
  end

  @doc """
  Returns a map of strength preset names to UBI option maps.
  """
  def strength_presets do
    %{
      "fast" => %{"Threads" => 1, "Depth" => 8, "Hash" => 64},
      "balanced" => %{"Threads" => 2, "Depth" => 12, "Hash" => 128},
      "strong" => %{"Threads" => 4, "Depth" => 15, "Hash" => 256}
    }
  end
end
