defmodule Bughouse.Games do
  @moduledoc """
  The Games context - game management and statistics.
  """

  import Ecto.Query, warn: false
  alias Bughouse.Repo
  alias Bughouse.Schemas.Games.{Game, GamePlayer}
  alias Bughouse.Accounts

  @topic_prefix "game:"

  @doc """
  Creates a new game with unique invite code.
  """
  def create_game(attrs \\ %{}) do
    invite_code = generate_invite_code()

    attrs =
      Map.merge(
        %{
          invite_code: invite_code,
          status: :waiting,
          time_control: "10min"
        },
        attrs
      )

    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a game by ID.
  """
  def get_game!(id), do: Repo.get!(Game, id)

  @doc """
  Gets a game by invite code.
  """
  def get_game_by_invite_code(code), do: Repo.get_by(Game, invite_code: code)
  def get_game_by_invite_code!(code), do: Repo.get_by!(Game, invite_code: code)

  @doc """
  Subscribes the current process to real-time updates for a game.

  Subscribe in LiveView mount to receive broadcasts when players join/leave or game starts.
  """
  def subscribe_to_game(invite_code) do
    Phoenix.PubSub.subscribe(Bughouse.PubSub, @topic_prefix <> invite_code)
  end

  @doc """
  Completes a game and updates all player stats.
  Called when game ends - writes everything to DB in one transaction.
  """
  def complete_game(game_id, completion_attrs) do
    Repo.transaction(fn ->
      # 1. Update game record
      game = Repo.get!(Game, game_id)

      {:ok, game} =
        game
        |> Game.changeset(Map.put(completion_attrs, :status, :completed))
        |> Repo.update()

      # 2. Create game_player records and update player stats
      # List of player outcomes
      player_results = completion_attrs.player_results

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
      join: gp2 in GamePlayer,
      on: gp.game_id == gp2.game_id,
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
      join: g in Game,
      on: gp.game_id == g.id,
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

  @doc """
  Joins a player to a specific position in a game.

  Returns `{:ok, updated_game}` or `{:error, reason}`.

  Error reasons:
  - `:game_not_found` - Game ID doesn't exist
  - `:game_already_started` - Game status is not :waiting
  - `:invalid_position` - Position is not one of the 4 valid positions
  - `:position_taken` - Position already occupied by another player
  - `:player_already_joined` - Player is already in a different position in this game
  """
  def join_game(game_id, player_id, position)
      when position in [:board_1_white, :board_1_black, :board_2_white, :board_2_black] do
    Repo.transaction(fn ->
      # Lock the game to prevent race conditions
      game =
        from(g in Game, where: g.id == ^game_id, lock: "FOR UPDATE")
        |> Repo.one()

      case validate_join(game, player_id, position) do
        :ok ->
          position_field = :"#{position}_id"
          attrs = %{position_field => player_id}

          game
          |> Game.changeset(attrs)
          |> Repo.update!()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, game} ->
        broadcast_game_update(game, :player_joined)
        {:ok, game}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def join_game(_game_id, _player_id, _position) do
    {:error, :invalid_position}
  end

  @doc """
  Joins a player to the first available position in a game.

  Returns `{:ok, {updated_game, assigned_position}}` or `{:error, reason}`.

  The assigned position is returned so the caller knows where they were placed.
  Positions are filled in order: board_1_white, board_1_black, board_2_white, board_2_black.
  """
  def join_game_random(game_id, player_id) do
    case Repo.get(Game, game_id) do
      nil ->
        {:error, :game_not_found}

      game ->
        case find_available_position(game) do
          nil ->
            {:error, :game_full}

          position ->
            case join_game(game_id, player_id, position) do
              {:ok, updated_game} ->
                # broadcast_game_update already called by join_game/3
                {:ok, {updated_game, position}}

              error ->
                error
            end
        end
    end
  end

  @doc """
  Starts a game (transitions from :waiting to :in_progress).

  Only works if all 4 positions are filled and game is in :waiting status.

  Returns `{:ok, updated_game}` or `{:error, reason}`.

  Error reasons:
  - `:game_not_found` - Game doesn't exist
  - `:game_already_started` - Game is not in :waiting status
  - `:not_enough_players` - Less than 4 players have joined
  """
  def start_game(game_id) do
    Repo.transaction(fn ->
      game =
        from(g in Game, where: g.id == ^game_id, lock: "FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(game) ->
          Repo.rollback(:game_not_found)

        game.status != :waiting ->
          Repo.rollback(:game_already_started)

        not game_full?(game) ->
          Repo.rollback(:not_enough_players)

        true ->
          game
          |> Game.changeset(%{status: :in_progress})
          |> Repo.update!()
      end
    end)
    |> case do
      {:ok, game} ->
        # Start the game server
        case start_game_server(game.id) do
          {:ok, pid} ->
            broadcast_game_update(game, :game_started)
            {:ok, game, pid}

          {:error, reason} ->
            require Logger
            Logger.error("Failed to start game server: #{inspect(reason)}")
            {:error, :server_start_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Removes a player from a game.

  Only works if the game is still in :waiting status.

  Returns `{:ok, updated_game}` or `{:error, reason}`.

  Error reasons:
  - `:game_not_found` - Game doesn't exist
  - `:cannot_leave` - Game has already started
  """
  def leave_game(game_id, player_id) do
    Repo.transaction(fn ->
      game =
        from(g in Game, where: g.id == ^game_id, lock: "FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(game) ->
          Repo.rollback(:game_not_found)

        game.status != :waiting ->
          Repo.rollback(:cannot_leave)

        true ->
          # Find and clear the player's position
          position_field =
            [:board_1_white_id, :board_1_black_id, :board_2_white_id, :board_2_black_id]
            |> Enum.find(fn field ->
              Map.get(game, field) == player_id
            end)

          if position_field do
            game
            |> Game.changeset(%{position_field => nil})
            |> Repo.update!()
          else
            # Player wasn't in the game, just return game unchanged
            game
          end
      end
    end)
    |> case do
      {:ok, game} ->
        broadcast_game_update(game, :player_left)
        {:ok, game}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a game with player names loaded.

  Returns a tuple of `{game, players_map}` where `players_map` is a map
  of player_id => display_name for all players in the game.
  """
  def get_game_with_players(invite_code) do
    game = get_game_by_invite_code!(invite_code)

    player_ids =
      [
        game.board_1_white_id,
        game.board_1_black_id,
        game.board_2_white_id,
        game.board_2_black_id
      ]
      |> Enum.filter(&(&1 != nil))

    players =
      if Enum.empty?(player_ids) do
        %{}
      else
        from(p in Bughouse.Schemas.Accounts.Player, where: p.id in ^player_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1.display_name})
      end

    {game, players}
  end

  defp validate_join(game, player_id, position) do
    cond do
      is_nil(game) ->
        {:error, :game_not_found}

      game.status != :waiting ->
        {:error, :game_already_started}

      Map.get(game, :"#{position}_id") != nil ->
        {:error, :position_taken}

      player_in_game?(game, player_id) ->
        {:error, :player_already_joined}

      true ->
        :ok
    end
  end

  defp find_available_position(%Game{} = game) do
    [:board_1_white, :board_1_black, :board_2_white, :board_2_black]
    |> Enum.find(fn position ->
      Map.get(game, :"#{position}_id") == nil
    end)
  end

  defp player_in_game?(%Game{} = game, player_id) do
    game.board_1_white_id == player_id or
      game.board_1_black_id == player_id or
      game.board_2_white_id == player_id or
      game.board_2_black_id == player_id
  end

  defp game_full?(%Game{} = game) do
    not is_nil(game.board_1_white_id) and
      not is_nil(game.board_1_black_id) and
      not is_nil(game.board_2_white_id) and
      not is_nil(game.board_2_black_id)
  end

  defp broadcast_game_update(game, event_type) do
    Phoenix.PubSub.broadcast(
      Bughouse.PubSub,
      @topic_prefix <> game.invite_code,
      {event_type, game}
    )
  end

  @doc """
  Starts a game server for an in-progress game.

  Should be called after start_game/1 transitions status to :in_progress.
  Returns {:ok, pid} or {:error, reason}.
  """
  def start_game_server(game_id) do
    DynamicSupervisor.start_child(
      Bughouse.Games.GameSupervisor,
      {Bughouse.Games.BughouseGameServer, game_id}
    )
  end

  @doc """
  Gets the PID of a running game server.

  Returns {:ok, pid} or {:error, :not_found}.
  """
  def get_game_server(game_id) do
    case Registry.lookup(Bughouse.Games.Registry, game_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Makes a move on a running game.
  """
  def make_game_move(game_id, player_id, move_notation) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.make_move(pid, player_id, move_notation)
    end
  end

  @doc """
  Drops a piece from reserves.
  """
  def drop_game_piece(game_id, player_id, piece_type, square) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.drop_piece(pid, player_id, piece_type, square)
    end
  end

  @doc """
  Player resigns from game.
  """
  def resign_game(game_id, player_id) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.resign(pid, player_id)
    end
  end

  @doc """
  Player offers a draw.
  """
  def offer_game_draw(game_id, player_id) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.offer_draw(pid, player_id)
    end
  end

  @doc """
  Gets the current game state from the game server.
  """
  def get_game_state(game_id) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.get_state(pid)
    end
  end

  @doc """
  Validates if a player can select a piece at the given square.
  Returns :ok if valid, {:error, reason} otherwise.
  """
  def can_select_piece?(game_id, player_id, square) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.can_select_piece?(pid, player_id, square)
    end
  end

  defp generate_invite_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode16()
  end
end
