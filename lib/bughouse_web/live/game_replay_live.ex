defmodule BughouseWeb.GameReplayLive do
  @moduledoc """
  LiveView for watching completed Bughouse games with video-like playback controls.

  Features:
  - Play/pause/scrub through game replay
  - Adjustable playback speed (1x-5x)
  - Smooth clock interpolation
  - Checkpoint system for instant scrubbing
  """
  use BughouseWeb, :live_view
  alias Bughouse.Games
  alias BughouseWeb.ReplayComponents
  require Logger

  @impl true
  def mount(%{"invite_code" => code}, _session, socket) do
    case Games.get_game_for_replay(code) do
      {:ok, game} ->
        Logger.info("GameReplayLive: Loading replay for game #{game.id} (#{code})")

        # Convert move keys from strings to atoms and sort chronologically
        # Timestamps are relative to game start (first move may be > 0 if player delayed)
        moves =
          game.moves
          |> Enum.map(&atomize_move/1)
          |> Enum.sort_by(& &1.timestamp)

        # Calculate game metadata
        initial_time_ms = parse_time_control(game.time_control)
        total_duration_ms = calculate_total_duration(moves)

        # Build player names map
        players = %{
          board_1_white: game.board_1_white.display_name,
          board_1_black: game.board_1_black.display_name,
          board_2_white: game.board_2_white.display_name,
          board_2_black: game.board_2_black.display_name
        }

        {:ok,
         assign(socket,
           game: game,
           players: players,
           move_history: moves,
           initial_time_ms: initial_time_ms,
           total_duration_ms: total_duration_ms,
           current_move_index: -1,
           playing: false,
           playback_speed: 2.0,
           # Initial board state (standard starting position)
           board_1_fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
           board_2_fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
           reserves: %{
             board_1_white: reserves_array_to_map([]),
             board_1_black: reserves_array_to_map([]),
             board_2_white: reserves_array_to_map([]),
             board_2_black: reserves_array_to_map([])
           },
           clocks: %{
             board_1_white: initial_time_ms,
             board_1_black: initial_time_ms,
             board_2_white: initial_time_ms,
             board_2_black: initial_time_ms
           }
         )}

      {:error, :not_found} ->
        Logger.warning("GameReplayLive: Game not found for code #{code}")

        {:ok,
         socket
         |> put_flash(:error, "Game not found")
         |> redirect(to: ~p"/")}

      {:error, :not_completed} ->
        Logger.info("GameReplayLive: Game #{code} not yet completed, redirecting to live game")

        {:ok,
         socket
         |> put_flash(:error, "This game is still in progress")
         |> redirect(to: ~p"/game/#{code}")}

      {:error, :no_moves} ->
        Logger.warning("GameReplayLive: Game #{code} has no recorded moves")

        {:ok,
         socket
         |> put_flash(:error, "No moves recorded for this game")
         |> redirect(to: ~p"/")}
    end
  end

  # Handle state updates from JavaScript hook
  # Clocks are updated locally in JavaScript via DOM manipulation
  @impl true
  def handle_event("update_state", state, socket) do
    # Each player has their own reserves
    reserves = %{
      board_1_white: reserves_array_to_map(state["board_1_white_reserves"] || []),
      board_1_black: reserves_array_to_map(state["board_1_black_reserves"] || []),
      board_2_white: reserves_array_to_map(state["board_2_white_reserves"] || []),
      board_2_black: reserves_array_to_map(state["board_2_black_reserves"] || [])
    }

    {:noreply,
     assign(socket,
       board_1_fen: state["board_1_fen"],
       board_2_fen: state["board_2_fen"],
       reserves: reserves,
       current_move_index: state["move_index"]
     )}
  end

  def handle_event("speed_changed", %{"speed" => speed}, socket) do
    {:noreply, assign(socket, :playback_speed, speed)}
  end

  def handle_event("playing_changed", %{"playing" => playing}, socket) do
    {:noreply, assign(socket, :playing, playing)}
  end

  # Convert reserve array ["p", "p", "n"] to map %{p: 2, n: 1, b: 0, r: 0, q: 0}
  defp reserves_array_to_map(reserves_list) when is_list(reserves_list) do
    # Count occurrences of each piece type
    counts =
      reserves_list
      |> Enum.frequencies()
      |> Enum.map(fn {piece, count} -> {String.to_atom(piece), count} end)
      |> Map.new()

    # Ensure all piece types are present (default to 0)
    %{
      p: Map.get(counts, :p, 0),
      n: Map.get(counts, :n, 0),
      b: Map.get(counts, :b, 0),
      r: Map.get(counts, :r, 0),
      q: Map.get(counts, :q, 0)
    }
  end

  defp parse_time_control(time_control) when is_binary(time_control) do
    # Parse formats like "10min", "5min", "3+2", etc.
    case Integer.parse(time_control) do
      {minutes, "min"} -> minutes * 60 * 1000
      {minutes, _} -> minutes * 60 * 1000
      # Default: 10 minutes
      _ -> 10 * 60 * 1000
    end
  end

  defp parse_time_control(_), do: 10 * 60 * 1000

  # Calculate total replay duration from game start to last move + buffer
  # Timestamps are relative to game start, so last move's timestamp is the duration
  # Add 3 seconds buffer to show final position clearly (especially king captures)
  defp calculate_total_duration(moves) when length(moves) > 0 do
    List.last(moves).timestamp + 3000
  end

  defp calculate_total_duration(_), do: 3000

  # Convert move map from string keys to atom keys
  # Database stores moves as JSON, which uses string keys
  # Also handles moves that already have atom keys (idempotent)
  defp atomize_move(move) when is_map(move) do
    # Helper to get value with either string or atom key
    get_field = fn map, key ->
      Map.get(map, key) || Map.get(map, to_string(key))
    end

    %{
      board: get_field.(move, :board),
      position:
        case get_field.(move, :position) do
          pos when is_atom(pos) -> pos
          pos when is_binary(pos) -> String.to_existing_atom(pos)
        end,
      type:
        case get_field.(move, :type) do
          t when is_atom(t) -> t
          t when is_binary(t) -> String.to_existing_atom(t)
        end,
      notation: get_field.(move, :notation),
      timestamp: get_field.(move, :timestamp),
      board_1_white_time: get_field.(move, :board_1_white_time),
      board_1_black_time: get_field.(move, :board_1_black_time),
      board_2_white_time: get_field.(move, :board_2_white_time),
      board_2_black_time: get_field.(move, :board_2_black_time),
      # Board states for replay
      board_1_fen: get_field.(move, :board_1_fen),
      board_2_fen: get_field.(move, :board_2_fen),
      # Each player has their own reserves
      board_1_white_reserves: get_field.(move, :board_1_white_reserves) || [],
      board_1_black_reserves: get_field.(move, :board_1_black_reserves) || [],
      board_2_white_reserves: get_field.(move, :board_2_white_reserves) || [],
      board_2_black_reserves: get_field.(move, :board_2_black_reserves) || []
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-7xl">
      <div class="mb-6">
        <h1 class="text-4xl font-bold">Game Replay</h1>
        <p class="text-base-content/70 mt-1">
          Game ID: <span class="font-mono">{@game.invite_code}</span>
          <span class="mx-2">•</span>
          Result:
          <span class="font-semibold">
            {format_result(@game.result, @players, @game.result_details)}
          </span>
        </p>
      </div>
      
    <!-- Two boards layout -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
        <!-- Board 1 -->
        <div class="flex flex-col">
          <!-- Top player (Black) with reserves -->
          <div class="mb-3">
            <div class="mb-1">
              <div class="font-semibold text-lg">{@players.board_1_black}</div>
              <div class="text-sm text-base-content/70">Board 1 • Black</div>
            </div>
            <.clock_and_reserves
              position={:board_1_black}
              time_ms={@clocks.board_1_black}
              active={false}
              reserves={@reserves.board_1_black}
              can_select={false}
            />
          </div>
          
    <!-- Chess Board -->
          <div id="replay-board-1" class="flex justify-center">
            <.chess_board fen={@board_1_fen} size="lg" flip={false} />
          </div>
          
    <!-- Bottom player (White) with reserves -->
          <div class="mt-3">
            <div class="mb-1">
              <div class="font-semibold text-lg">{@players.board_1_white}</div>
              <div class="text-sm text-base-content/70">Board 1 • White</div>
            </div>
            <.clock_and_reserves
              position={:board_1_white}
              time_ms={@clocks.board_1_white}
              active={false}
              reserves={@reserves.board_1_white}
              can_select={false}
            />
          </div>
        </div>
        
    <!-- Board 2 -->
        <div class="flex flex-col">
          <!-- Top player (White) with reserves -->
          <div class="mb-3">
            <div class="mb-1">
              <div class="font-semibold text-lg">{@players.board_2_white}</div>
              <div class="text-sm text-base-content/70">Board 2 • White</div>
            </div>
            <.clock_and_reserves
              position={:board_2_white}
              time_ms={@clocks.board_2_white}
              active={false}
              reserves={@reserves.board_2_white}
              can_select={false}
            />
          </div>
          
    <!-- Chess Board -->
          <div id="replay-board-2" class="flex justify-center">
            <.chess_board fen={@board_2_fen} size="lg" flip={true} />
          </div>
          
    <!-- Bottom player (Black) with reserves -->
          <div class="mt-3">
            <div class="mb-1">
              <div class="font-semibold text-lg">{@players.board_2_black}</div>
              <div class="text-sm text-base-content/70">Board 2 • Black</div>
            </div>
            <.clock_and_reserves
              position={:board_2_black}
              time_ms={@clocks.board_2_black}
              active={false}
              reserves={@reserves.board_2_black}
              can_select={false}
            />
          </div>
        </div>
      </div>
      
    <!-- Replay controls -->
      <div class="space-y-4 max-w-4xl mx-auto">
        <ReplayComponents.replay_controls
          playing={@playing}
          speed={@playback_speed}
          current_move={@current_move_index}
          total_moves={length(@move_history)}
        />

        <ReplayComponents.replay_progress_bar
          progress={calculate_progress(@current_move_index, @move_history)}
          move_markers={generate_move_markers(@move_history, @total_duration_ms)}
        />
      </div>
      
    <!-- Hidden element to pass data to JavaScript hook -->
      <div
        id="replay-data"
        phx-hook="ReplayPlayer"
        data-moves={Jason.encode!(@move_history)}
        data-total-duration={@total_duration_ms}
        data-state-version={@current_move_index}
        class="hidden"
      />
    </div>
    """
  end

  defp format_result(result, players, result_details) do
    reason = get_reason_text(result_details)

    case result do
      "team_1_wins" ->
        {names, verb} = format_team_names(players.board_1_white, players.board_2_black)
        "#{names} #{verb} by #{reason}"

      "team_2_wins" ->
        {names, verb} = format_team_names(players.board_1_black, players.board_2_white)
        "#{names} #{verb} by #{reason}"

      "draw" ->
        "Game drawn by #{reason}"

      _ ->
        "Unknown"
    end
  end

  defp format_team_names(name, name) when name != nil, do: {name, "wins"}
  defp format_team_names(nil, nil), do: {"Team", "wins"}
  defp format_team_names(p1, nil), do: {p1, "wins"}
  defp format_team_names(nil, p2), do: {p2, "wins"}
  defp format_team_names(p1, p2), do: {"#{p1} and #{p2}", "win"}

  defp get_reason_text(nil), do: "unknown"

  defp get_reason_text(details) when is_map(details) do
    reason = details["reason"] || Map.get(details, :reason)
    format_reason_string(reason)
  end

  defp get_reason_text(_), do: "unknown"

  defp format_reason_string("king_captured"), do: "king capture"
  defp format_reason_string("timeout"), do: "timeout"
  defp format_reason_string("checkmate"), do: "checkmate"
  defp format_reason_string("resignation"), do: "resignation"
  defp format_reason_string("agreement"), do: "mutual agreement"
  defp format_reason_string("stalemate"), do: "stalemate"
  defp format_reason_string("threefold_repetition"), do: "threefold repetition"
  defp format_reason_string("fifty_move_rule"), do: "fifty-move rule"
  defp format_reason_string("insufficient_material"), do: "insufficient material"
  defp format_reason_string(nil), do: "unknown"
  defp format_reason_string(reason) when is_binary(reason), do: reason
  defp format_reason_string(reason), do: to_string(reason)

  defp calculate_progress(_current_move_index, []), do: 0.0

  # Before first move (index -1) - show 0%
  defp calculate_progress(current_move_index, _moves) when current_move_index < 0, do: 0.0

  defp calculate_progress(current_move_index, moves) when current_move_index >= length(moves) do
    100.0
  end

  defp calculate_progress(current_move_index, moves) do
    current_move = Enum.at(moves, current_move_index)
    last_move = List.last(moves)

    if current_move && last_move && last_move.timestamp > 0 do
      # Progress based on actual game time, not move count
      current_move.timestamp / last_move.timestamp * 100
    else
      0.0
    end
  end

  defp generate_move_markers([], _total_duration_ms), do: []

  defp generate_move_markers(moves, total_duration_ms) when total_duration_ms > 0 do
    moves
    |> Enum.with_index(1)
    # Show marker every 10 seconds of game time
    |> Enum.filter(fn {move, _idx} ->
      rem(div(move.timestamp, 10_000), 1) == 0 && move.timestamp > 0
    end)
    |> Enum.map(fn {move, idx} ->
      # Calculate percentage based on total duration (including buffer)
      percent = move.timestamp / total_duration_ms * 100
      {idx, percent}
    end)
  end

  defp generate_move_markers(_moves, _total_duration_ms), do: []
end
