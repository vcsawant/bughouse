defmodule Bughouse.Games do
  @moduledoc """
  The Games context - game management and statistics.
  """

  import Ecto.Query, warn: false
  alias Bughouse.Repo
  alias Bughouse.Games.{Game, GamePlayer}
  alias Bughouse.Accounts

  @doc """
  Creates a new game with unique invite code.
  """
  def create_game(attrs \\ %{}) do
    invite_code = generate_invite_code()

    attrs = Map.merge(%{
      invite_code: invite_code,
      status: :waiting,
      time_control: "10min"
    }, attrs)

    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a game by invite code.
  """
  def get_game_by_invite_code(code), do: Repo.get_by(Game, invite_code: code)
  def get_game_by_invite_code!(code), do: Repo.get_by!(Game, invite_code: code)

  @doc """
  Completes a game and updates all player stats.
  Called when game ends - writes everything to DB in one transaction.
  """
  def complete_game(game_id, completion_attrs) do
    Repo.transaction(fn ->
      # 1. Update game record
      game = Repo.get!(Game, game_id)
      {:ok, game} = game
      |> Game.changeset(Map.put(completion_attrs, :status, :completed))
      |> Repo.update()

      # 2. Create game_player records and update player stats
      player_results = completion_attrs.player_results  # List of player outcomes

      Enum.each(player_results, fn player_result ->
        # Create game_player record
        %GamePlayer{}
        |> GamePlayer.changeset(Map.put(player_result, :game_id, game.id))
        |> Repo.insert!()

        # Update player stats
        player = Accounts.get_player!(player_result.player_id)
        Accounts.update_player_stats(player, player_result)
      end)

      game
    end)
  end

  @doc """
  Get player's overall record.
  """
  def get_player_record(player_id) do
    from(gp in GamePlayer,
      where: gp.player_id == ^player_id and gp.outcome != :incomplete,
      group_by: gp.outcome,
      select: {gp.outcome, count(gp.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Get stats against a specific friend.
  """
  def get_stats_vs_friend(player_id, friend_id) do
    from(gp in GamePlayer,
      join: gp2 in GamePlayer, on: gp.game_id == gp2.game_id,
      where: gp.player_id == ^player_id and gp2.player_id == ^friend_id,
      where: gp.outcome != :incomplete,
      group_by: gp.outcome,
      select: {gp.outcome, count(gp.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Get winrate by color.
  """
  def get_color_stats(player_id) do
    from(gp in GamePlayer,
      where: gp.player_id == ^player_id and gp.outcome != :incomplete,
      group_by: gp.color,
      select: %{
        color: gp.color,
        total: count(gp.id),
        wins: filter(count(gp.id), gp.won == true)
      }
    )
    |> Repo.all()
  end

  @doc """
  Get rating history over time.
  """
  def get_rating_history(player_id) do
    from(gp in GamePlayer,
      where: gp.player_id == ^player_id and not is_nil(gp.rating_after),
      order_by: [asc: gp.created_at],
      select: %{
        timestamp: gp.created_at,
        rating: gp.rating_after,
        change: gp.rating_change
      }
    )
    |> Repo.all()
  end

  @doc """
  Get stats by time control.
  """
  def get_time_control_stats(player_id) do
    from(gp in GamePlayer,
      join: g in Game, on: gp.game_id == g.id,
      where: gp.player_id == ^player_id and gp.outcome != :incomplete,
      group_by: g.time_control,
      select: %{
        time_control: g.time_control,
        total: count(gp.id),
        wins: filter(count(gp.id), gp.won == true)
      }
    )
    |> Repo.all()
  end

  defp generate_invite_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode16()
  end
end
