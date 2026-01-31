defmodule Bughouse.Games.BughouseGameServer do
  @moduledoc """
  GenServer managing a complete Bughouse chess game.

  Coordinates two chess boards, four players, synchronized timers,
  team-based piece reserves, and win condition detection.
  """
  use GenServer
  require Logger

  alias Bughouse.Games

  defstruct [
    # Game metadata
    :game_id,
    :invite_code,

    # Board processes (binbo_bughouse)
    :board_1_pid,
    :board_2_pid,

    # Player IDs
    :board_1_white_id,
    :board_1_black_id,
    :board_2_white_id,
    :board_2_black_id,

    # Clock state (event-driven)
    # %{board_1_white: int, board_1_black: int, ...}
    :time_remaining_ms,
    # %{board_1_white: int | nil, ...}
    :clock_started_at_ms,
    # %{board_1_white: ref | nil, ...}
    :timeout_refs,
    # MapSet.t() - which clocks are running
    :active_clocks,

    # Move history for DB persistence
    :move_history,

    # Game result
    :result,
    :result_reason,
    :result_details,
    :result_timestamp,

    # Draw offers
    :draw_offers
  ]

  ## Public API

  @doc """
  Starts a game server for the given game ID.
  """
  @spec start_link(binary()) :: GenServer.on_start()
  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  @doc """
  Makes a move on the game.
  """
  @spec make_move(pid(), binary(), String.t()) :: :ok | {:error, atom()}
  def make_move(pid, player_id, move_notation) do
    GenServer.call(pid, {:make_move, player_id, move_notation})
  end

  @doc """
  Drops a piece from reserves.
  """
  @spec drop_piece(pid(), binary(), atom(), String.t()) :: :ok | {:error, atom()}
  def drop_piece(pid, player_id, piece_type, square) do
    GenServer.call(pid, {:drop_piece, player_id, piece_type, square})
  end

  @doc """
  Player resigns.
  """
  @spec resign(pid(), binary()) :: :ok
  def resign(pid, player_id) do
    GenServer.call(pid, {:resign, player_id})
  end

  @doc """
  Player offers a draw.
  """
  @spec offer_draw(pid(), binary()) :: :ok
  def offer_draw(pid, player_id) do
    GenServer.call(pid, {:offer_draw, player_id})
  end

  @doc """
  Validates if a player can select a piece at the given square.
  Returns :ok if valid, {:error, reason} otherwise.
  """
  @spec can_select_piece?(pid(), binary(), String.t()) :: :ok | {:error, atom()}
  def can_select_piece?(pid, player_id, square) do
    GenServer.call(pid, {:can_select_piece, player_id, square})
  end

  @doc """
  Gets current game state for client.
  """
  @spec get_state(pid()) :: {:ok, map()}
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Stops the game server.
  """
  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  ## GenServer Callbacks

  @impl true
  def init(game_id) do
    # Load game from database
    game = Games.get_game!(game_id)

    # Ensure game is in correct status
    if game.status != :in_progress do
      {:stop, {:error, :game_not_in_progress}}
    else
      # Start binbo processes for both boards
      {:ok, board_1_pid} = :binbo_bughouse.new_server()
      {:ok, board_2_pid} = :binbo_bughouse.new_server()

      # Initialize both boards in bughouse mode
      {:ok, :continue} = :binbo_bughouse.new_game(board_1_pid, :initial, %{mode: :bughouse})
      {:ok, :continue} = :binbo_bughouse.new_game(board_2_pid, :initial, %{mode: :bughouse})

      # Parse time control
      initial_time_ms = parse_time_control(game.time_control)
      now = System.monotonic_time(:millisecond)

      # Initialize clock state
      time_remaining_ms = %{
        board_1_white: initial_time_ms,
        board_1_black: initial_time_ms,
        board_2_white: initial_time_ms,
        board_2_black: initial_time_ms
      }

      clock_started_at_ms = %{
        # White clocks start immediately
        board_1_white: now,
        board_1_black: nil,
        # White clocks start immediately
        board_2_white: now,
        board_2_black: nil
      }

      # Schedule timeout messages for both whites (they start first)
      timeout_ref_b1w = Process.send_after(self(), {:timeout, :board_1_white}, initial_time_ms)
      timeout_ref_b2w = Process.send_after(self(), {:timeout, :board_2_white}, initial_time_ms)

      timeout_refs = %{
        board_1_white: timeout_ref_b1w,
        board_1_black: nil,
        board_2_white: timeout_ref_b2w,
        board_2_black: nil
      }

      # Initialize state
      state = %__MODULE__{
        game_id: game.id,
        invite_code: game.invite_code,
        board_1_pid: board_1_pid,
        board_2_pid: board_2_pid,
        board_1_white_id: game.board_1_white_id,
        board_1_black_id: game.board_1_black_id,
        board_2_white_id: game.board_2_white_id,
        board_2_black_id: game.board_2_black_id,
        time_remaining_ms: time_remaining_ms,
        clock_started_at_ms: clock_started_at_ms,
        timeout_refs: timeout_refs,
        # Both whites start
        active_clocks: MapSet.new([:board_1_white, :board_2_white]),
        move_history: [],
        result: nil,
        result_reason: nil,
        result_details: nil,
        result_timestamp: nil,
        draw_offers: MapSet.new()
      }

      Logger.info("BughouseGameServer started for game #{game.invite_code}")

      {:ok, state}
    end
  end

  @impl true
  def handle_call({:make_move, player_id, move_notation}, _from, state) do
    if state.result != nil do
      {:reply, {:error, :game_over}, state}
    else
      position = get_player_position(state, player_id)

      # Validate it's the player's turn
      if position == nil or not MapSet.member?(state.active_clocks, position) do
        {:reply, {:error, :not_your_turn}, state}
      else
        # Determine which board
        {board_num, board_pid} = get_board_for_position(state, position)

        # Query capture info BEFORE making the move
        {from_square, to_square} = parse_move_squares(move_notation)

        capture_info =
          :binbo_bughouse.get_capture_info(board_pid, from_square, to_square)

        # Attempt the move
        case :binbo_bughouse.move(board_pid, move_notation) do
          {:ok, :continue} ->
            new_state =
              state
              |> handle_capture_if_any(capture_info, position)
              |> record_move(board_num, position, :move, move_notation)
              |> update_clocks_after_move(position)
              |> broadcast_state_update()

            {:reply, :ok, new_state}

          {:ok, {:king_captured, winner}} ->
            winning_team = binbo_winner_to_team(winner, board_num)

            new_state =
              state
              |> record_move(board_num, position, :move, move_notation)
              |> end_game(winning_team, :king_captured, %{board: board_num, winner: winner})
              |> persist_to_database()
              |> broadcast_game_over()

            {:reply, :ok, new_state}

          {:ok, {:checkmate, winner}} ->
            winning_team = binbo_winner_to_team(winner, board_num)

            new_state =
              state
              |> record_move(board_num, position, :move, move_notation)
              |> end_game(winning_team, :checkmate, %{board: board_num, winner: winner})
              |> persist_to_database()
              |> broadcast_game_over()

            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
    end
  end

  @impl true
  def handle_call({:drop_piece, player_id, piece_type, square}, _from, state) do
    if state.result != nil do
      {:reply, {:error, :game_over}, state}
    else
      position = get_player_position(state, player_id)

      if position == nil or not MapSet.member?(state.active_clocks, position) do
        {:reply, {:error, :not_your_turn}, state}
      else
        {board_num, board_pid} = get_board_for_position(state, position)

        # Attempt drop
        case :binbo_bughouse.drop_move(board_pid, piece_type, square) do
          {:ok, :continue} ->
            new_state =
              state
              |> record_move(board_num, position, :drop, "#{piece_type}@#{square}")
              |> update_clocks_after_move(position)
              |> broadcast_state_update()

            {:reply, :ok, new_state}

          {:ok, game_over_result} when is_tuple(game_over_result) ->
            # Handle game over from drop (rare but possible)
            {status_type, winner} = game_over_result
            winning_team = binbo_winner_to_team(winner, board_num)

            new_state =
              state
              |> record_move(board_num, position, :drop, "#{piece_type}@#{square}")
              |> end_game(winning_team, status_type, %{board: board_num})
              |> persist_to_database()
              |> broadcast_game_over()

            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
    end
  end

  @impl true
  def handle_call({:resign, player_id}, _from, state) do
    if state.result != nil do
      {:reply, {:error, :game_already_over}, state}
    else
      position = get_player_position(state, player_id)

      if position == nil do
        {:reply, {:error, :not_in_game}, state}
      else
        # Determine which team resigned
        team = position_to_team(position)
        winning_team = opposite_team(team)

        new_state =
          state
          |> end_game(winning_team, :resignation, %{resigning_player: player_id})
          |> persist_to_database()
          |> broadcast_game_over()

        {:reply, :ok, new_state}
      end
    end
  end

  @impl true
  def handle_call({:offer_draw, player_id}, _from, state) do
    if state.result != nil do
      {:reply, {:error, :game_already_over}, state}
    else
      new_draw_offers = MapSet.put(state.draw_offers, player_id)

      # Check if all 4 players have offered draw
      all_players =
        MapSet.new([
          state.board_1_white_id,
          state.board_1_black_id,
          state.board_2_white_id,
          state.board_2_black_id
        ])

      if MapSet.equal?(new_draw_offers, all_players) do
        # All players agreed to draw
        new_state =
          %{state | draw_offers: new_draw_offers}
          |> end_game(:draw, :agreement, %{})
          |> persist_to_database()
          |> broadcast_game_over()

        {:reply, :ok, new_state}
      else
        {:reply, :ok, %{state | draw_offers: new_draw_offers}}
      end
    end
  end

  @impl true
  def handle_call({:can_select_piece, player_id, square}, _from, state) do
    if state.result != nil do
      {:reply, {:error, :game_over}, state}
    else
      position = get_player_position(state, player_id)

      # Check if player is in the game
      if position == nil do
        {:reply, {:error, :not_in_game}, state}
      # Check if it's the player's turn
      else if not MapSet.member?(state.active_clocks, position) do
        {:reply, {:error, :not_your_turn}, state}
      else
        # Get the board and check if there's a valid piece at the square
        {_board_num, board_pid} = get_board_for_position(state, position)
        player_color = position_to_color(position)

        case get_piece_at_square(board_pid, square, player_color) do
          {:ok, legal_moves} ->
            {:reply, {:ok, legal_moves}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
      end
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    client_state = serialize_state_for_client(state)
    {:reply, {:ok, client_state}, state}
  end

  @impl true
  def handle_info({:timeout, position}, state) do
    # Check if this timeout is still valid (clock still active)
    if MapSet.member?(state.active_clocks, position) do
      # Player actually timed out
      Logger.info("Player #{position} timed out in game #{state.invite_code}")

      losing_team = position_to_team(position)
      winning_team = opposite_team(losing_team)

      new_state =
        state
        |> end_game(winning_team, :timeout, %{position: position})
        |> persist_to_database()
        |> broadcast_game_over()

      {:noreply, new_state}
    else
      # Timeout was cancelled (move was made), ignore
      Logger.debug("Ignoring cancelled timeout for #{position}")
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel all active timeouts
    Enum.each(state.timeout_refs, fn {_position, ref} ->
      if ref, do: Process.cancel_timer(ref)
    end)

    # Stop binbo processes
    if state.board_1_pid, do: :binbo_bughouse.stop_server(state.board_1_pid)
    if state.board_2_pid, do: :binbo_bughouse.stop_server(state.board_2_pid)

    # Persist incomplete game if crashed
    if state.result == nil do
      persist_incomplete_game(state)
    end

    :ok
  end

  ## Private Helpers

  defp via_tuple(game_id) do
    {:via, Registry, {Bughouse.Games.Registry, game_id}}
  end

  defp parse_time_control("1sec"), do: 1 * 1000
  defp parse_time_control("5min"), do: 5 * 60 * 1000
  defp parse_time_control("10min"), do: 10 * 60 * 1000

  defp parse_time_control(other) do
    Logger.warning("Unknown time control format: #{other}, defaulting to 5min")
    5 * 60 * 1000
  end

  defp get_player_position(state, player_id) do
    cond do
      state.board_1_white_id == player_id -> :board_1_white
      state.board_1_black_id == player_id -> :board_1_black
      state.board_2_white_id == player_id -> :board_2_white
      state.board_2_black_id == player_id -> :board_2_black
      true -> nil
    end
  end

  defp get_board_for_position(state, position)
       when position in [:board_1_white, :board_1_black] do
    {1, state.board_1_pid}
  end

  defp get_board_for_position(state, position)
       when position in [:board_2_white, :board_2_black] do
    {2, state.board_2_pid}
  end

  defp parse_move_squares(move_notation) do
    # Extract from and to squares from notation like "e2e4"
    <<from::binary-size(2), to::binary-size(2), _rest::binary>> = move_notation
    {from, to}
  end

  defp handle_capture_if_any(state, {:ok, {piece_type, was_promoted}}, capturing_position) do
    add_piece_to_reserves(state, capturing_position, piece_type, was_promoted)
  end

  defp handle_capture_if_any(state, {:ok, :no_capture}, _position) do
    state
  end

  defp handle_capture_if_any(state, error, _position) do
    Logger.warning("Unexpected capture info result: #{inspect(error)}")
    state
  end

  defp add_piece_to_reserves(state, capturing_position, piece_type, was_promoted) do
    # Demote if promoted
    reserve_piece = if was_promoted, do: :p, else: piece_type

    # Skip if king
    if reserve_piece == :k do
      state
    else
      # Determine teammate's board and reserve color
      {teammate_board_pid, reserve_color} =
        case capturing_position do
          :board_1_white -> {state.board_2_pid, :black}
          :board_1_black -> {state.board_2_pid, :white}
          :board_2_white -> {state.board_1_pid, :black}
          :board_2_black -> {state.board_1_pid, :white}
        end

      :binbo_bughouse.add_to_reserve(teammate_board_pid, reserve_color, reserve_piece)
      state
    end
  end

  defp record_move(state, board_num, position, move_type, notation) do
    now = System.monotonic_time(:millisecond)
    current_clocks = calculate_current_clocks(state, now)

    move_record = %{
      board: board_num,
      position: position,
      type: move_type,
      notation: notation,
      timestamp: now,
      board_1_white_time: current_clocks.board_1_white,
      board_1_black_time: current_clocks.board_1_black,
      board_2_white_time: current_clocks.board_2_white,
      board_2_black_time: current_clocks.board_2_black
    }

    %{state | move_history: [move_record | state.move_history]}
  end

  defp update_clocks_after_move(state, position) do
    now = System.monotonic_time(:millisecond)

    # 1. Calculate time used by player who just moved
    clock_start = Map.fetch!(state.clock_started_at_ms, position)
    elapsed = now - clock_start
    old_time = Map.fetch!(state.time_remaining_ms, position)
    new_time = max(0, old_time - elapsed)

    # 2. Cancel current timeout
    if ref = Map.get(state.timeout_refs, position) do
      Process.cancel_timer(ref)
    end

    # 3. Determine opponent
    opponent = get_opponent(position)

    # 4. Schedule opponent's timeout
    opponent_time = Map.fetch!(state.time_remaining_ms, opponent)
    opponent_timeout_ref = Process.send_after(self(), {:timeout, opponent}, opponent_time)

    # 5. Update state
    state
    |> put_in([Access.key!(:time_remaining_ms), position], new_time)
    |> put_in([Access.key!(:clock_started_at_ms), position], nil)
    |> put_in([Access.key!(:timeout_refs), position], nil)
    |> put_in([Access.key!(:clock_started_at_ms), opponent], now)
    |> put_in([Access.key!(:timeout_refs), opponent], opponent_timeout_ref)
    |> Map.update!(:active_clocks, fn clocks ->
      clocks |> MapSet.delete(position) |> MapSet.put(opponent)
    end)
  end

  defp get_opponent(:board_1_white), do: :board_1_black
  defp get_opponent(:board_1_black), do: :board_1_white
  defp get_opponent(:board_2_white), do: :board_2_black
  defp get_opponent(:board_2_black), do: :board_2_white

  defp calculate_current_clocks(state, now) do
    Enum.into(state.time_remaining_ms, %{}, fn {position, time_remaining} ->
      current_time =
        if MapSet.member?(state.active_clocks, position) do
          # Clock is active, subtract elapsed time
          clock_start = Map.fetch!(state.clock_started_at_ms, position)
          elapsed = now - clock_start
          max(0, time_remaining - elapsed)
        else
          # Clock is not active, return stored value
          time_remaining
        end

      {position, current_time}
    end)
  end

  defp position_to_team(position) when position in [:board_1_white, :board_2_black], do: :team_1
  defp position_to_team(position) when position in [:board_1_black, :board_2_white], do: :team_2

  defp opposite_team(:team_1), do: :team_2
  defp opposite_team(:team_2), do: :team_1

  defp binbo_winner_to_team(:white_wins, 1), do: :team_1
  defp binbo_winner_to_team(:black_wins, 1), do: :team_2
  defp binbo_winner_to_team(:white_wins, 2), do: :team_2
  defp binbo_winner_to_team(:black_wins, 2), do: :team_1

  defp position_to_color(:board_1_white), do: :white
  defp position_to_color(:board_1_black), do: :black
  defp position_to_color(:board_2_white), do: :white
  defp position_to_color(:board_2_black), do: :black

  # Validate piece at square using binbo_bughouse's select_square
  defp get_piece_at_square(board_pid, square, player_color) do
    case :binbo_bughouse.select_square(board_pid, square) do
      {:ok, {:empty, _moves}} ->
        {:error, :empty_square}

      {:ok, {piece_char, legal_moves}} when is_integer(piece_char) ->
        # Uppercase = white (A-Z: 65-90), lowercase = black (a-z: 97-122)
        piece_color = if piece_char >= ?A and piece_char <= ?Z, do: :white, else: :black

        if piece_color == player_color do
          {:ok, legal_moves}
        else
          {:error, :opponent_piece}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp end_game(state, result, reason, details) do
    # Cancel all timeout timers
    for {_position, ref} <- state.timeout_refs, ref != nil do
      Process.cancel_timer(ref)
    end

    %{
      state
      | result: result,
        result_reason: reason,
        result_details: details,
        result_timestamp: DateTime.utc_now(),
        # Clear all active clocks when game ends
        active_clocks: MapSet.new(),
        timeout_refs: %{
          board_1_white: nil,
          board_1_black: nil,
          board_2_white: nil,
          board_2_black: nil
        }
    }
  end

  defp persist_to_database(state) do
    # Get final FENs
    {:ok, board_1_fen} = :binbo_bughouse.get_fen(state.board_1_pid)
    {:ok, board_2_fen} = :binbo_bughouse.get_fen(state.board_2_pid)

    # Get reserves (we only need board_1 reserves for serialization)
    {:ok, board_1_reserves} = :binbo_bughouse.get_reserves(state.board_1_pid)

    # Convert result to string
    result_string =
      case state.result do
        :team_1 -> "team_1_wins"
        :team_1_wins -> "team_1_wins"
        :team_2 -> "team_2_wins"
        :team_2_wins -> "team_2_wins"
        :draw -> "draw"
      end

    # Build player results
    player_results = build_player_results(state)

    # Build completion attrs
    completion_attrs = %{
      result: result_string,
      result_details: state.result_details,
      result_timestamp: state.result_timestamp,
      final_board_1_fen: to_string(board_1_fen),
      final_board_2_fen: to_string(board_2_fen),
      final_white_reserves: serialize_reserves(board_1_reserves.white),
      final_black_reserves: serialize_reserves(board_1_reserves.black),
      moves: Enum.reverse(state.move_history),
      player_results: player_results
    }

    # Call Games.complete_game/2
    case Games.complete_game(state.game_id, completion_attrs) do
      {:ok, _game} ->
        Logger.info("Game #{state.invite_code} persisted to database")
        state

      {:error, reason} ->
        Logger.error("Failed to persist game #{state.invite_code}: #{inspect(reason)}")
        state
    end
  end

  defp persist_incomplete_game(state) do
    Logger.warning("Game #{state.invite_code} terminated incomplete, persisting partial state")
    # TODO: Implement incomplete game persistence
    :ok
  end

  defp build_player_results(state) do
    team_1_outcome =
      case state.result do
        :team_1 -> :win
        :team_1_wins -> :win
        :team_2 -> :loss
        :team_2_wins -> :loss
        :draw -> :draw
      end

    team_2_outcome =
      case state.result do
        :team_1 -> :loss
        :team_1_wins -> :loss
        :team_2 -> :win
        :team_2_wins -> :win
        :draw -> :draw
      end

    # Get player ratings for rating_before
    # For now, we'll use a default or fetch from DB
    # In a real implementation, these should be fetched before the game starts
    [
      %{
        player_id: state.board_1_white_id,
        outcome: team_1_outcome,
        won: team_1_outcome == :win,
        position: "board_1_white",
        color: "white",
        board: 1,
        rating_before: 1200,
        rating_after: 1200,
        rating_change: 0
      },
      %{
        player_id: state.board_1_black_id,
        outcome: team_2_outcome,
        won: team_2_outcome == :win,
        position: "board_1_black",
        color: "black",
        board: 1,
        rating_before: 1200,
        rating_after: 1200,
        rating_change: 0
      },
      %{
        player_id: state.board_2_white_id,
        outcome: team_2_outcome,
        won: team_2_outcome == :win,
        position: "board_2_white",
        color: "white",
        board: 2,
        rating_before: 1200,
        rating_after: 1200,
        rating_change: 0
      },
      %{
        player_id: state.board_2_black_id,
        outcome: team_1_outcome,
        won: team_1_outcome == :win,
        position: "board_2_black",
        color: "black",
        board: 2,
        rating_before: 1200,
        rating_after: 1200,
        rating_change: 0
      }
    ]
  end

  defp serialize_reserves(reserve_map) do
    reserve_map
    |> Enum.flat_map(fn {piece, count} ->
      List.duplicate(Atom.to_string(piece), count)
    end)
  end

  defp broadcast_state_update(state) do
    Phoenix.PubSub.broadcast(
      Bughouse.PubSub,
      "game:#{state.invite_code}",
      {:game_state_update, serialize_state_for_client(state)}
    )

    state
  end

  defp broadcast_game_over(state) do
    Phoenix.PubSub.broadcast(
      Bughouse.PubSub,
      "game:#{state.invite_code}",
      {:game_over, serialize_state_for_client(state)}
    )

    state
  end

  defp serialize_state_for_client(state) do
    {:ok, board_1_fen} = :binbo_bughouse.get_fen(state.board_1_pid)
    {:ok, board_2_fen} = :binbo_bughouse.get_fen(state.board_2_pid)
    {:ok, board_1_reserves} = :binbo_bughouse.get_reserves(state.board_1_pid)
    {:ok, board_2_reserves} = :binbo_bughouse.get_reserves(state.board_2_pid)

    # Calculate current clock values (subtract elapsed time from active clocks)
    now = System.monotonic_time(:millisecond)
    current_clocks = calculate_current_clocks(state, now)

    %{
      # Extract only piece placement (first part of FEN before space)
      # Full FEN: "rnbqkbnr/pppppppp/.../RNBQKBNR w KQkq - 0 1"
      # If there are reserved pieces "rnbqkbnr/pppppppp/.../RNBQKBNR[ppr] w KQkq - 0 1"
      # We only need: "rnbqkbnr/pppppppp/.../RNBQKBNR"
      board_1_fen: extract_piece_placement(board_1_fen),
      board_2_fen: extract_piece_placement(board_2_fen),
      clocks: current_clocks,
      active_clocks: MapSet.to_list(state.active_clocks),
      reserves: %{
        # Each player's reserves are stored on their own board with their own color
        # When a teammate captures a piece, it's added to this player's reserves
        board_1_white: board_1_reserves.white,
        board_1_black: board_1_reserves.black,
        board_2_white: board_2_reserves.white,
        board_2_black: board_2_reserves.black
      },
      last_move: List.first(state.move_history),
      result: state.result,
      result_reason: state.result_reason
    }
  end

  # Extract piece placement from full FEN string
  # FEN format: "piece_placement active_color castling en_passant halfmove fullmove"
  # Returns only the piece_placement part
  defp extract_piece_placement(fen) when is_binary(fen) do
    fen
    |> String.split([" ", "["], parts: 2)
    |> List.first()
  end

  defp extract_piece_placement(fen), do: to_string(fen)

  ## Child Spec

  def child_spec(game_id) do
    %{
      id: {__MODULE__, game_id},
      start: {__MODULE__, :start_link, [game_id]},
      restart: :temporary,
      type: :worker
    }
  end
end
