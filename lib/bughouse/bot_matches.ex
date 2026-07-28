defmodule Bughouse.BotMatches do
  @moduledoc """
  Context for bot match management — automated bot-vs-bot game series.

  A BotMatch orchestrates N sequential games between two bots, alternating
  sides for fairness, and tracks aggregate results.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Bughouse.Repo
  alias Bughouse.Schemas.Games.{BotMatch, BotMatchGame}
  alias Ecto.Multi

  ## CRUD

  def create_match(attrs) do
    %BotMatch{}
    |> BotMatch.changeset(attrs)
    |> Repo.insert()
  end

  def get_match!(id), do: Repo.get!(BotMatch, id)

  def get_match_with_games(id) do
    BotMatch
    |> Repo.get!(id)
    |> Repo.preload([
      bot_a: :player,
      bot_b: :player,
      current_game: [],
      bot_match_games: {from(g in BotMatchGame, order_by: [asc: g.game_number]), [:game]}
    ])
  end

  def list_matches_for_player(player_id) do
    from(m in BotMatch,
      where: m.created_by_id == ^player_id,
      order_by: [desc: m.inserted_at],
      preload: [bot_a: :player, bot_b: :player]
    )
    |> Repo.all()
  end

  def change_match(match, attrs \\ %{}) do
    BotMatch.changeset(match, attrs)
  end

  ## Match Lifecycle

  def start_match(%BotMatch{} = match) do
    match
    |> BotMatch.changeset(%{status: "running", started_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
    |> case do
      {:ok, match} ->
        start_match_server(match.id)
        {:ok, match}

      error ->
        error
    end
  end

  def complete_match(%BotMatch{} = match) do
    match
    |> BotMatch.changeset(%{
      status: "completed",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      current_game_id: nil
    })
    |> Repo.update()
  end

  def cancel_match(%BotMatch{} = match) do
    match
    |> BotMatch.changeset(%{
      status: "cancelled",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def update_current_game(%BotMatch{} = match, game_id) do
    match
    |> BotMatch.changeset(%{current_game_id: game_id})
    |> Repo.update()
  end

  ## Game Result Recording

  def record_game_result(%BotMatch{} = match, game_id, game_number, result, bot_a_team) do
    Multi.new()
    |> Multi.insert(:match_game, fn _changes ->
      BotMatchGame.changeset(%BotMatchGame{}, %{
        bot_match_id: match.id,
        game_id: game_id,
        game_number: game_number,
        result: result,
        bot_a_team: bot_a_team
      })
    end)
    |> Multi.update(:match, fn _changes ->
      counters =
        case result do
          "bot_a_win" -> %{completed_games: match.completed_games + 1, bot_a_wins: match.bot_a_wins + 1}
          "bot_b_win" -> %{completed_games: match.completed_games + 1, bot_b_wins: match.bot_b_wins + 1}
          "draw" -> %{completed_games: match.completed_games + 1, draws: match.draws + 1}
        end

      BotMatch.changeset(match, counters)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{match: match}} -> {:ok, match}
      {:error, _op, changeset, _} -> {:error, changeset}
    end
  end

  ## PubSub

  def subscribe_to_match(match_id) do
    Phoenix.PubSub.subscribe(Bughouse.PubSub, "bot_match:#{match_id}")
  end

  def broadcast_match_update(match) do
    Phoenix.PubSub.broadcast(
      Bughouse.PubSub,
      "bot_match:#{match.id}",
      {:match_update, match}
    )
  end

  def broadcast_match_completed(match_id) do
    Phoenix.PubSub.broadcast(
      Bughouse.PubSub,
      "bot_match:#{match_id}",
      {:match_completed, match_id}
    )
  end

  ## Supervision

  def start_match_server(match_id) do
    DynamicSupervisor.start_child(
      Bughouse.BotMatches.MatchSupervisor,
      {Bughouse.BotMatches.BotMatchServer, match_id}
    )
  end

  ## Helpers

  @time_control_map %{
    60_000 => "1min",
    180_000 => "3min",
    300_000 => "5min"
  }

  def time_control_ms_to_string(ms) do
    Map.get(@time_control_map, ms, "#{div(ms, 60_000)}min")
  end
end
