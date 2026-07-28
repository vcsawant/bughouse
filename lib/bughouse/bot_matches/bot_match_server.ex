defmodule Bughouse.BotMatches.BotMatchServer do
  @moduledoc """
  GenServer that orchestrates a bot match — a series of games between two bots
  with side alternation for fairness. Supports running multiple games in parallel.

  One instance per active match, supervised under MatchSupervisor.

  Failure handling:
    * Engine process crash → the crashed bot's team resigns immediately and the
      game is recorded with result_reason "forfeit_crash".
    * Game server crash → the game is retried once (same game number, so seat
      parity is preserved); a second failure records an "aborted" draw.
    * Failed game starts are retried on a timer instead of stalling the match.
    * Completed/cancelled games have their game server and engines stopped so
      long overnight matches don't accumulate processes.
  """
  use GenServer
  require Logger

  alias Bughouse.{Games, BotMatches}

  # Brief delay between starting games to let previous engines clean up
  @game_start_delay_ms 500
  # Delay before reaping a finished game's processes — engines need time to
  # process the game_over broadcast (send game_result metadata + quit) first
  @game_cleanup_delay_ms 1_000
  # Retry delay when game slots couldn't be filled (e.g. bot_limit_reached)
  @fill_retry_delay_ms 5_000

  defstruct [
    :match_id,
    :bot_a,
    :bot_b,
    :total_games,
    :time_control_ms,
    :parallel_games,
    # Next fresh game number to assign (increments as games are started)
    :next_game_number,
    # Map of invite_code => %{game_id, game_number, bot_a_team, monitor_ref,
    #                         crashed_bot_player_id, retried}
    active_games: %{},
    # Game numbers waiting to be retried after a game-server crash
    retry_queue: []
  ]

  ## Public API

  def start_link(match_id) do
    GenServer.start_link(__MODULE__, match_id)
  end

  def cancel(pid) do
    GenServer.cast(pid, :cancel)
  end

  @doc """
  Seat assignment for a game: odd game numbers seat bot_a as team_1,
  even game numbers as team_2, so board advantages cancel over a match.
  """
  def bot_a_team_for_game(game_number) when rem(game_number, 2) == 1, do: :team_1
  def bot_a_team_for_game(_game_number), do: :team_2

  @doc """
  Maps a game result (winning team or draw) to a match result relative to bot_a.
  """
  def map_game_result(:team_1, :team_1), do: "bot_a_win"
  def map_game_result(:team_2, :team_1), do: "bot_b_win"
  def map_game_result(:team_1, :team_2), do: "bot_b_win"
  def map_game_result(:team_2, :team_2), do: "bot_a_win"
  def map_game_result(:draw, _), do: "draw"
  def map_game_result(_, _), do: "draw"

  ## GenServer Callbacks

  @impl true
  def init(match_id) do
    match = BotMatches.get_match_with_games(match_id)

    if match.status in ["completed", "cancelled"] do
      {:stop, :normal}
    else
      Registry.register(Bughouse.Games.Registry, {:bot_match, match_id}, nil)

      state = %__MODULE__{
        match_id: match_id,
        bot_a: match.bot_a,
        bot_b: match.bot_b,
        total_games: match.total_games,
        time_control_ms: match.time_control_ms,
        parallel_games: match.parallel_games || 1,
        next_game_number: match.completed_games + 1
      }

      Logger.info(
        "BotMatchServer started: #{match.bot_a.display_name} vs #{match.bot_b.display_name}, " <>
          "#{match.total_games} games (#{state.parallel_games} parallel), " <>
          "starting at game #{state.next_game_number}"
      )

      send(self(), :fill_game_slots)
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:fill_game_slots, state) do
    state = fill_game_slots(state)

    cond do
      not games_remaining?(state) and map_size(state.active_games) == 0 ->
        # All games started and all have completed
        match = BotMatches.get_match!(state.match_id)
        {:ok, match} = BotMatches.complete_match(match)
        BotMatches.broadcast_match_completed(state.match_id)

        Logger.info(
          "BotMatchServer: match #{state.match_id} completed — " <>
            "#{match.bot_a_wins}-#{match.draws}-#{match.bot_b_wins}"
        )

        {:stop, :normal, state}

      games_remaining?(state) and map_size(state.active_games) < state.parallel_games ->
        # Couldn't fill all slots (e.g. bot_limit_reached) — retry later
        Process.send_after(self(), :fill_game_slots, @fill_retry_delay_ms)
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  # Game completed — identify which game, record result, fill more slots
  def handle_info({:game_over, game_state}, state) do
    # Find which active game this belongs to by checking all subscribed games
    case find_completed_game(state) do
      {invite_code, game_info} ->
        handle_game_completion(state, invite_code, game_info, game_state)

      nil ->
        # Couldn't identify the game — might be a stale message
        Logger.warning("BotMatchServer: received game_over but couldn't match to active game")
        {:noreply, state}
    end
  end

  # An engine process died mid-game — forfeit that game immediately instead of
  # waiting for the crashed bot to lose on time
  def handle_info({:engine_exited, %{game_id: game_id, bot_player_id: bot_player_id}}, state) do
    case Enum.find(state.active_games, fn {_code, gi} -> gi.game_id == game_id end) do
      nil ->
        {:noreply, state}

      {invite_code, %{crashed_bot_player_id: nil} = game_info} ->
        Logger.warning(
          "BotMatchServer: engine crash in game #{game_info.game_number} " <>
            "(bot #{bot_player_id}), forfeiting"
        )

        # Resign ends the game right away; if it fails (e.g. game server already
        # down), the clock timeout / :DOWN paths are the backstop
        Games.resign_game(game_id, bot_player_id)

        game_info = %{game_info | crashed_bot_player_id: bot_player_id}
        {:noreply, %{state | active_games: Map.put(state.active_games, invite_code, game_info)}}

      _already_marked ->
        {:noreply, state}
    end
  end

  # A game server died without producing a result — retry the game once,
  # then record it as aborted
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Enum.find(state.active_games, fn {_code, gi} -> gi.monitor_ref == ref end) do
      nil ->
        {:noreply, state}

      {invite_code, game_info} ->
        Logger.error(
          "BotMatchServer: game server for game #{game_info.game_number} died: " <>
            inspect(reason)
        )

        Bughouse.BotEngine.Supervisor.stop_engines_for_game(game_info.game_id)
        Games.abort_game(game_info.game_id)
        state = %{state | active_games: Map.delete(state.active_games, invite_code)}

        state =
          if game_info.retried do
            record_aborted_game(state, game_info)
          else
            %{state | retry_queue: state.retry_queue ++ [game_info.game_number]}
          end

        Process.send_after(self(), :fill_game_slots, @game_start_delay_ms)
        {:noreply, state}
    end
  end

  # Deferred cleanup of a finished game's processes
  def handle_info({:cleanup_game, game_id}, state) do
    Bughouse.BotEngine.Supervisor.stop_engines_for_game(game_id)
    Games.stop_game_server(game_id)
    {:noreply, state}
  end

  # Ignore other PubSub messages from games
  def handle_info({:game_state_update, _}, state), do: {:noreply, state}
  def handle_info({:game_started, _}, state), do: {:noreply, state}
  def handle_info({:player_joined, _}, state), do: {:noreply, state}
  def handle_info({:player_left, _}, state), do: {:noreply, state}
  def handle_info({:team_message, _}, state), do: {:noreply, state}

  @impl true
  def handle_cast(:cancel, state) do
    Logger.info("BotMatchServer: match #{state.match_id} cancelled")
    cleanup_active_games(state)
    match = BotMatches.get_match!(state.match_id)
    {:ok, match} = BotMatches.cancel_match(match)
    BotMatches.broadcast_match_update(match)
    {:stop, :normal, %{state | active_games: %{}}}
  end

  @impl true
  def terminate(:normal, _state), do: :ok

  def terminate(_reason, state) do
    # Abnormal exit — don't strand running games and engine processes
    cleanup_active_games(state)
    :ok
  end

  ## Private — Game Slot Management

  defp games_remaining?(state) do
    state.next_game_number <= state.total_games or state.retry_queue != []
  end

  defp fill_game_slots(state) do
    if map_size(state.active_games) < state.parallel_games and games_remaining?(state) do
      # Stagger starts slightly to avoid port collisions
      if map_size(state.active_games) > 0, do: Process.sleep(@game_start_delay_ms)

      {game_num, retried, state} = take_next_game(state)

      case start_game(state, game_num, retried) do
        {:ok, state} ->
          fill_game_slots(state)

        {:error, reason} ->
          Logger.error("BotMatchServer: failed to start game #{game_num}: #{inspect(reason)}")

          # Put the game back so a later :fill_game_slots retries it
          requeue_failed_start(state, game_num, retried)
      end
    else
      state
    end
  end

  defp take_next_game(%{retry_queue: [game_num | rest]} = state) do
    {game_num, true, %{state | retry_queue: rest}}
  end

  defp take_next_game(state) do
    {state.next_game_number, false, %{state | next_game_number: state.next_game_number + 1}}
  end

  defp requeue_failed_start(state, game_num, _retried) do
    %{state | retry_queue: [game_num | state.retry_queue]}
  end

  defp start_game(state, game_num, retried) do
    bot_a_team = bot_a_team_for_game(game_num)
    tc_string = BotMatches.time_control_ms_to_string(state.time_control_ms)

    match_metadata = %{
      "match_id" => state.match_id,
      "total_games" => state.total_games,
      "time_control" => state.time_control_ms,
      "game_number" => game_num
    }

    with {:ok, game} <-
           Games.create_game(%{time_control: tc_string, match_metadata: match_metadata}),
         {:ok, _} <- Games.join_game_as_dual_bot(game.id, state.bot_a.player_id, bot_a_team),
         {:ok, _} <-
           Games.join_game_as_dual_bot(
             game.id,
             state.bot_b.player_id,
             if(bot_a_team == :team_1, do: :team_2, else: :team_1)
           ),
         :ok <- Games.subscribe_to_game(game.invite_code),
         {:ok, _game, pid} <- Games.start_game(game.id) do
      game_info = %{
        game_id: game.id,
        game_number: game_num,
        bot_a_team: bot_a_team,
        monitor_ref: Process.monitor(pid),
        crashed_bot_player_id: nil,
        retried: retried
      }

      Logger.info(
        "BotMatchServer: started game #{game_num}/#{state.total_games} " <>
          "(#{game.invite_code}), bot_a=#{bot_a_team}#{if retried, do: " (retry)", else: ""}"
      )

      # Update current_game_id to the most recently started game (for UI "watch live")
      match = BotMatches.get_match!(state.match_id)
      BotMatches.update_current_game(match, game.id)
      BotMatches.broadcast_match_update(match)

      {:ok, %{state | active_games: Map.put(state.active_games, game.invite_code, game_info)}}
    end
  end

  ## Private — Game Completion

  defp find_completed_game(state) do
    # When running sequentially (1 game), there's only one active game
    # When running in parallel, we check the game server for each active game
    # to find the one that has a result set
    case Map.to_list(state.active_games) do
      [{invite_code, game_info}] ->
        # Only one active game, must be this one
        {invite_code, game_info}

      games when length(games) > 1 ->
        # Multiple active games — check which one has completed
        Enum.find_value(games, fn {invite_code, game_info} ->
          case Games.get_game_state(game_info.game_id) do
            {:ok, %{result: result}} when result != nil ->
              {invite_code, game_info}

            _ ->
              nil
          end
        end)

      [] ->
        nil
    end
  end

  defp handle_game_completion(state, invite_code, game_info, game_state) do
    result = map_game_result(game_state[:result], game_info.bot_a_team)
    reason = result_reason(game_info, game_state)

    Logger.info(
      "BotMatchServer: game #{game_info.game_number}/#{state.total_games} " <>
        "result=#{result} reason=#{reason} (game_result=#{inspect(game_state[:result])}, " <>
        "bot_a_team=#{game_info.bot_a_team})"
    )

    match = BotMatches.get_match!(state.match_id)
    bot_a_team_str = Atom.to_string(game_info.bot_a_team)

    {:ok, updated_match} =
      BotMatches.record_game_result(
        match,
        game_info.game_id,
        game_info.game_number,
        result,
        bot_a_team_str,
        reason
      )

    BotMatches.broadcast_match_update(updated_match)

    # Remove completed game; reap its processes once engines have had time to
    # log the result, then schedule filling slots
    Process.demonitor(game_info.monitor_ref, [:flush])
    Process.send_after(self(), {:cleanup_game, game_info.game_id}, @game_cleanup_delay_ms)
    state = %{state | active_games: Map.delete(state.active_games, invite_code)}
    Process.send_after(self(), :fill_game_slots, @game_start_delay_ms)
    {:noreply, state}
  end

  defp result_reason(%{crashed_bot_player_id: crashed}, _game_state) when crashed != nil do
    "forfeit_crash"
  end

  defp result_reason(_game_info, game_state) do
    to_string(game_state[:result_reason] || "unknown")
  end

  defp record_aborted_game(state, game_info) do
    Logger.error(
      "BotMatchServer: game #{game_info.game_number} failed twice, recording as aborted"
    )

    match = BotMatches.get_match!(state.match_id)

    case BotMatches.record_game_result(
           match,
           game_info.game_id,
           game_info.game_number,
           "draw",
           Atom.to_string(game_info.bot_a_team),
           "aborted"
         ) do
      {:ok, updated_match} ->
        BotMatches.broadcast_match_update(updated_match)

      {:error, changeset} ->
        Logger.error("BotMatchServer: failed to record aborted game: #{inspect(changeset)}")
    end

    state
  end

  ## Private — Cleanup

  defp cleanup_active_games(state) do
    for {_invite_code, game_info} <- state.active_games do
      Process.demonitor(game_info.monitor_ref, [:flush])
      Games.stop_game_server(game_info.game_id)
      Bughouse.BotEngine.Supervisor.stop_engines_for_game(game_info.game_id)
      Games.abort_game(game_info.game_id)
    end

    :ok
  end

  ## Child Spec

  def child_spec(match_id) do
    %{
      id: {__MODULE__, match_id},
      start: {__MODULE__, :start_link, [match_id]},
      restart: :temporary,
      type: :worker
    }
  end
end
