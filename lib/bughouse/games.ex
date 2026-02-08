defmodule Bughouse.Games do
  @moduledoc """
  The Games context - game management and statistics.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Bughouse.Repo
  alias Bughouse.Schemas.Games.{Game, GamePlayer}
  alias Bughouse.Accounts
  alias Bughouse.BotEngine

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
          time_control: "5min"
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
  Gets a completed game with all data needed for replay.

  Returns `{:ok, game}` with preloaded players if successful, or:
  - `{:error, :not_found}` if game doesn't exist
  - `{:error, :not_completed}` if game is still in progress
  - `{:error, :no_moves}` if game has no recorded moves

  ## Examples

      iex> get_game_for_replay("ABC123")
      {:ok, %Game{moves: [...], board_1_white: %Player{}, ...}}

      iex> get_game_for_replay("invalid")
      {:error, :not_found}
  """
  def get_game_for_replay(invite_code) do
    case get_game_by_invite_code(invite_code) do
      nil ->
        {:error, :not_found}

      %Game{status: status} = _game when status != :completed ->
        {:error, :not_completed}

      %Game{moves: []} = _game ->
        {:error, :no_moves}

      game ->
        # Preload all players for display
        game =
          Repo.preload(game, [
            :board_1_white,
            :board_1_black,
            :board_2_white,
            :board_2_black
          ])

        {:ok, game}
    end
  end

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

      # 2. Create game_player records (one per seat, even for dual bots)
      player_results = completion_attrs.player_results

      Enum.each(player_results, fn player_result ->
        %GamePlayer{}
        |> GamePlayer.changeset(Map.put(player_result, :game_id, game.id))
        |> Repo.insert!()
      end)

      # 3. Update player stats (once per unique player, not per seat)
      player_results
      |> Enum.uniq_by(& &1.player_id)
      |> Enum.each(fn player_result ->
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
  Get friend stats distinguishing teammate vs opponent games.

  Team 1 = board_1_white + board_2_black
  Team 2 = board_1_black + board_2_white

  Returns %{total_games: n, wins_with: n, wins_against: n}
  """
  def get_friend_stats(player_id, friend_id) do
    # Find all completed games where both players participated
    games =
      from(gp1 in GamePlayer,
        join: gp2 in GamePlayer,
        on: gp1.game_id == gp2.game_id,
        join: g in Game,
        on: g.id == gp1.game_id,
        where: gp1.player_id == ^player_id and gp2.player_id == ^friend_id,
        where: gp1.outcome != :incomplete,
        select: %{
          won: gp1.won,
          # Determine if they were on the same team
          same_team:
            fragment(
              """
              CASE
                WHEN (? IN (?, ?) AND ? IN (?, ?)) THEN true
                WHEN (? IN (?, ?) AND ? IN (?, ?)) THEN true
                ELSE false
              END
              """,
              type(^player_id, Ecto.UUID),
              g.board_1_white_id,
              g.board_2_black_id,
              type(^friend_id, Ecto.UUID),
              g.board_1_white_id,
              g.board_2_black_id,
              type(^player_id, Ecto.UUID),
              g.board_1_black_id,
              g.board_2_white_id,
              type(^friend_id, Ecto.UUID),
              g.board_1_black_id,
              g.board_2_white_id
            )
        }
      )
      |> Repo.all()

    total = length(games)

    wins_with =
      Enum.count(games, fn g -> g.same_team && g.won end)

    wins_against =
      Enum.count(games, fn g -> !g.same_team && g.won end)

    %{total_games: total, wins_with: wins_with, wins_against: wins_against}
  end

  @doc """
  Get winrate by color.
  """
  def get_color_stats(player_id) do
    # Color is derived from the game's position assignments: a player played white
    # if they hold board_1_white or board_2_white in that game.
    # Note: dual-position bots play both colors in one game — this stat is for
    # human players only and will exclude bots when is_bot is added to players.
    from(gp in GamePlayer,
      join: g in Game,
      on: gp.game_id == g.id,
      where: gp.player_id == ^player_id and gp.outcome != :incomplete,
      group_by:
        fragment(
          "CASE WHEN ? = ? OR ? = ? THEN 'white' ELSE 'black' END",
          g.board_1_white_id,
          ^player_id,
          g.board_2_white_id,
          ^player_id
        ),
      select: %{
        color:
          fragment(
            "CASE WHEN ? = ? OR ? = ? THEN 'white' ELSE 'black' END",
            g.board_1_white_id,
            ^player_id,
            g.board_2_white_id,
            ^player_id
          ),
        total: count(gp.id),
        wins: filter(count(gp.id), gp.won == true)
      }
    )
    |> Repo.all()
  end

  @doc """
  Get rating history over time, optionally filtered by time period.

  Time periods: :day, :month, :three_months, or nil for all time.
  """
  def get_rating_history(player_id, time_period \\ nil) do
    base_query =
      from(gp in GamePlayer,
        where: gp.player_id == ^player_id and not is_nil(gp.rating_after),
        order_by: [asc: gp.created_at],
        select: %{
          timestamp: gp.created_at,
          rating: gp.rating_after,
          change: gp.rating_change
        }
      )

    query =
      case time_period do
        :day ->
          cutoff = DateTime.utc_now() |> DateTime.add(-1, :day)
          from(gp in base_query, where: gp.created_at >= ^cutoff)

        :month ->
          cutoff = DateTime.utc_now() |> DateTime.add(-30, :day)
          from(gp in base_query, where: gp.created_at >= ^cutoff)

        :three_months ->
          cutoff = DateTime.utc_now() |> DateTime.add(-90, :day)
          from(gp in base_query, where: gp.created_at >= ^cutoff)

        _ ->
          base_query
      end

    Repo.all(query)
  end

  @doc """
  Lists recent completed games for a player with all players preloaded.

  Returns list of tuples: {game, game_player}
  - game: The full game record with all 4 players preloaded
  - game_player: The GamePlayer record for this player

  Ordered by most recent first, limited to specified count (default 100).
  """
  def list_player_games(player_id, limit \\ 100) do
    from(gp in GamePlayer,
      where: gp.player_id == ^player_id,
      join: g in assoc(gp, :game),
      where: g.status == :completed,
      distinct: gp.game_id,
      order_by: [desc: gp.created_at],
      limit: ^limit,
      select: {g, gp}
    )
    |> Repo.all()
    |> Enum.map(fn {game, game_player} ->
      # Preload all 4 players for each game
      game =
        Repo.preload(game, [
          :board_1_white,
          :board_1_black,
          :board_2_white,
          :board_2_black
        ])

      {game, game_player}
    end)
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
  Fills both seats of a team with a single dual-mode bot in one transaction.
  `team` is `:team_1` or `:team_2`.

  Team 1 = board_1_white + board_2_black
  Team 2 = board_1_black + board_2_white

  Intentionally skips the player_in_game? guard — a dual bot legitimately
  occupies two seats.
  """
  def join_game_as_dual_bot(game_id, player_id, team) do
    {pos_a, pos_b} = team_positions(team)

    Repo.transaction(fn ->
      game =
        from(g in Game, where: g.id == ^game_id, lock: "FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(game) ->
          Repo.rollback(:game_not_found)

        game.status != :waiting ->
          Repo.rollback(:game_already_started)

        Map.get(game, :"#{pos_a}_id") != nil ->
          Repo.rollback(:position_taken)

        Map.get(game, :"#{pos_b}_id") != nil ->
          Repo.rollback(:position_taken)

        true ->
          game
          |> Game.changeset(%{:"#{pos_a}_id" => player_id, :"#{pos_b}_id" => player_id})
          |> Repo.update!()
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
          # Check bot limit before starting
          bot_positions = get_bot_positions(game)
          engines_needed = length(bot_positions)

          if engines_needed > 0 and engines_needed > BotEngine.Supervisor.available_slots() do
            Repo.rollback(:bot_limit_reached)
          end

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
            # Start bot engines (if any bots are playing)
            start_bot_engines(game)
            broadcast_game_update(game, :game_started)
            {:ok, game, pid}

          {:error, reason} ->
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
  Removes a player from ALL positions in a game.
  Intended for bot removal where a dual bot occupies two seats.
  """
  def leave_game_all_positions(game_id, player_id) do
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
          attrs =
            [:board_1_white_id, :board_1_black_id, :board_2_white_id, :board_2_black_id]
            |> Enum.filter(fn field -> Map.get(game, field) == player_id end)
            |> Map.new(&{&1, nil})

          game
          |> Game.changeset(attrs)
          |> Repo.update!()
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

  defp team_positions(:team_1), do: {:board_1_white, :board_2_black}
  defp team_positions(:team_2), do: {:board_1_black, :board_2_white}

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
  def make_game_move(game_id, player_id, move_notation, position \\ nil) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.make_move(pid, player_id, move_notation, position)
    end
  end

  @doc """
  Drops a piece from reserves.
  """
  def drop_game_piece(game_id, player_id, piece_type, square, position \\ nil) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.drop_piece(pid, player_id, piece_type, square, position)
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
  Used for the game live view so it needs only display relevant state.
  """
  def get_game_state(game_id) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.get_state(pid)
    end
  end

  @doc """
  Gets raw BFEN strings and current clocks from the game server.
  Used by BotEngineServer to feed positions to the Rust engine.
  """
  def get_bfen(game_id) do
    with {:ok, pid} <- get_game_server(game_id) do
      Bughouse.Games.BughouseGameServer.get_bfen(pid)
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

  ## Bot Engine Helpers

  @doc false
  # Returns a list of {bot_player_id, [position_atoms]} for each distinct bot in the game.
  defp get_bot_positions(game) do
    # Collect all player_id → position mappings
    position_map = [
      {game.board_1_white_id, :board_1_white},
      {game.board_1_black_id, :board_1_black},
      {game.board_2_white_id, :board_2_white},
      {game.board_2_black_id, :board_2_black}
    ]

    # Get unique player IDs (a dual bot occupies two seats with same ID)
    unique_ids =
      position_map
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()

    # Check which are bots
    bot_ids =
      from(p in Bughouse.Schemas.Accounts.Player,
        where: p.id in ^unique_ids and p.is_bot == true,
        select: p.id
      )
      |> Repo.all()
      |> MapSet.new()

    # Build {bot_id, [positions]} for each bot
    position_map
    |> Enum.filter(fn {player_id, _pos} -> MapSet.member?(bot_ids, player_id) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.to_list()
  end

  defp start_bot_engines(game) do
    bot_positions = get_bot_positions(game)

    Enum.each(bot_positions, fn {bot_player_id, positions} ->
      case BotEngine.Supervisor.start_engine(
             game.id,
             game.invite_code,
             bot_player_id,
             positions
           ) do
        {:ok, _pid} ->
          Logger.info("Started bot engine for #{bot_player_id} in game #{game.invite_code}")

        {:error, reason} ->
          Logger.error("Failed to start bot engine for #{bot_player_id}: #{inspect(reason)}")
      end
    end)
  end
end
