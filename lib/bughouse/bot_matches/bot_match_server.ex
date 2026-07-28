defmodule Bughouse.BotMatches.BotMatchServer do
  @moduledoc """
  GenServer that orchestrates a bot match — a series of games between two bots
  with side alternation for fairness. Supports running multiple games in parallel.

  One instance per active match, supervised under MatchSupervisor.
  """
  use GenServer
  require Logger

  alias Bughouse.{Games, BotMatches}

  # Brief delay between starting games to let previous engines clean up
  @game_start_delay_ms 500

  defstruct [
    :match_id,
    :bot_a,
    :bot_b,
    :total_games,
    :time_control_ms,
    :parallel_games,
    # Next game number to assign (increments as games are started)
    :next_game_number,
    # Map of invite_code => %{game_id, game_number, bot_a_team}
    :active_games
  ]

  ## Public API

  def start_link(match_id) do
    GenServer.start_link(__MODULE__, match_id)
  end

  def cancel(pid) do
    GenServer.cast(pid, :cancel)
  end

  ## GenServer Callbacks

  @impl true
  def init(match_id) do
    match = BotMatches.get_match_with_games(match_id)

    if match.status in ["completed", "cancelled"] do
      {:stop, :normal}
    else
      state = %__MODULE__{
        match_id: match_id,
        bot_a: match.bot_a,
        bot_b: match.bot_b,
        total_games: match.total_games,
        time_control_ms: match.time_control_ms,
        parallel_games: match.parallel_games || 1,
        next_game_number: match.completed_games + 1,
        active_games: %{}
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

    if state.next_game_number > state.total_games and map_size(state.active_games) == 0 do
      # All games started and all have completed
      match = BotMatches.get_match!(state.match_id)
      {:ok, match} = BotMatches.complete_match(match)
      BotMatches.broadcast_match_completed(state.match_id)

      Logger.info(
        "BotMatchServer: match #{state.match_id} completed — " <>
          "#{match.bot_a_wins}-#{match.draws}-#{match.bot_b_wins}"
      )

      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  # Game completed — identify which game, record result, fill more slots
  def handle_info({:game_over, game_state}, state) do
    # Find which active game this belongs to by checking all subscribed games
    # The PubSub message arrives on the game's topic, so we need to match
    # We identify by checking which active game has a matching result state
    case find_completed_game(state) do
      {invite_code, game_info} ->
        handle_game_completion(state, invite_code, game_info, game_state)

      nil ->
        # Couldn't identify the game — might be a stale message
        Logger.warning("BotMatchServer: received game_over but couldn't match to active game")
        {:noreply, state}
    end
  end

  # Ignore other PubSub messages from games
  def handle_info({:game_state_update, _}, state), do: {:noreply, state}
  def handle_info({:game_started, _}, state), do: {:noreply, state}
  def handle_info({:player_joined, _}, state), do: {:noreply, state}
  def handle_info({:player_left, _}, state), do: {:noreply, state}

  @impl true
  def handle_cast(:cancel, state) do
    Logger.info("BotMatchServer: match #{state.match_id} cancelled")
    match = BotMatches.get_match!(state.match_id)
    {:ok, match} = BotMatches.cancel_match(match)
    BotMatches.broadcast_match_update(match)
    {:stop, :normal, state}
  end

  ## Private — Game Slot Management

  defp fill_game_slots(state) do
    slots_to_fill = state.parallel_games - map_size(state.active_games)
    games_remaining = state.total_games - state.next_game_number + 1
    to_start = min(slots_to_fill, games_remaining)

    if to_start <= 0 do
      state
    else
      Enum.reduce(1..to_start, state, fn i, acc ->
        # Add a small staggered delay for each game to avoid port collisions
        if i > 1, do: Process.sleep(@game_start_delay_ms)

        case start_game(acc) do
          {:ok, new_state} ->
            new_state

          {:error, reason} ->
            Logger.error(
              "BotMatchServer: failed to start game #{acc.next_game_number}: #{inspect(reason)}"
            )

            acc
        end
      end)
    end
  end

  defp start_game(state) do
    game_num = state.next_game_number

    # Alternate sides: odd games bot_a=team_1, even games bot_a=team_2
    bot_a_team = if rem(game_num, 2) == 1, do: :team_1, else: :team_2

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
         {:ok, _game, _pid} <- Games.start_game(game.id) do
      game_info = %{
        game_id: game.id,
        game_number: game_num,
        bot_a_team: bot_a_team
      }

      Logger.info(
        "BotMatchServer: started game #{game_num}/#{state.total_games} " <>
          "(#{game.invite_code}), bot_a=#{bot_a_team}"
      )

      # Update current_game_id to the most recently started game (for UI "watch live")
      match = BotMatches.get_match!(state.match_id)
      BotMatches.update_current_game(match, game.id)
      BotMatches.broadcast_match_update(match)

      {:ok,
       %{
         state
         | next_game_number: game_num + 1,
           active_games: Map.put(state.active_games, game.invite_code, game_info)
       }}
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

    Logger.info(
      "BotMatchServer: game #{game_info.game_number}/#{state.total_games} " <>
        "result=#{result} (game_result=#{inspect(game_state[:result])}, " <>
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
        bot_a_team_str
      )

    BotMatches.broadcast_match_update(updated_match)

    # Remove completed game and schedule filling slots (with delay for engine cleanup)
    state = %{state | active_games: Map.delete(state.active_games, invite_code)}
    Process.send_after(self(), :fill_game_slots, @game_start_delay_ms)
    {:noreply, state}
  end

  defp map_game_result(:team_1, :team_1), do: "bot_a_win"
  defp map_game_result(:team_2, :team_1), do: "bot_b_win"
  defp map_game_result(:team_1, :team_2), do: "bot_b_win"
  defp map_game_result(:team_2, :team_2), do: "bot_a_win"
  defp map_game_result(:draw, _), do: "draw"
  defp map_game_result(_, _), do: "draw"

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
