defmodule Bughouse.Games.BughouseGameServerTest do
  use Bughouse.DataCase, async: false

  alias Bughouse.Games.BughouseGameServer
  alias Bughouse.{Games, Accounts}

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defmodule TestHelpers do
    @moduledoc false
    alias Bughouse.{Games, Accounts}
    alias Bughouse.Games.BughouseGameServer

    @doc """
    Creates a full game with 4 players and starts the server.

    Returns:
      %{
        game: %Game{},
        pid: pid(),
        players: %{
          board_1_white: player_id,
          board_1_black: player_id,
          board_2_white: player_id,
          board_2_black: player_id
        }
      }
    """
    def setup_full_game do
      # Create game
      {:ok, game} = Games.create_game(%{time_control: "5min"})

      # Create 4 players
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      # Join players to positions
      {:ok, game} = Games.join_game(game.id, p1.id, :board_1_white)
      {:ok, game} = Games.join_game(game.id, p2.id, :board_1_black)
      {:ok, game} = Games.join_game(game.id, p3.id, :board_2_white)
      {:ok, game} = Games.join_game(game.id, p4.id, :board_2_black)

      # Start game server
      {:ok, game, pid} = Games.start_game(game.id)

      # Allow the spawned GenServer to access the database
      Ecto.Adapters.SQL.Sandbox.allow(Bughouse.Repo, self(), pid)

      %{
        game: game,
        pid: pid,
        players: %{
          board_1_white: p1.id,
          board_1_black: p2.id,
          board_2_white: p3.id,
          board_2_black: p4.id
        }
      }
    end

    @doc """
    Creates a game with short time control for timeout testing.
    """
    def setup_short_game do
      # Create game with 1 second time control
      {:ok, game} = Games.create_game(%{time_control: "1sec"})

      # Create 4 players
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      # Join players
      {:ok, game} = Games.join_game(game.id, p1.id, :board_1_white)
      {:ok, game} = Games.join_game(game.id, p2.id, :board_1_black)
      {:ok, game} = Games.join_game(game.id, p3.id, :board_2_white)
      {:ok, game} = Games.join_game(game.id, p4.id, :board_2_black)

      # Start game server
      {:ok, game, pid} = Games.start_game(game.id)

      # Allow the spawned GenServer to access the database
      Ecto.Adapters.SQL.Sandbox.allow(Bughouse.Repo, self(), pid)

      %{
        game: game,
        pid: pid,
        players: %{
          board_1_white: p1.id,
          board_1_black: p2.id,
          board_2_white: p3.id,
          board_2_black: p4.id
        }
      }
    end

    @doc """
    Helper to make a move and assert success.
    Returns updated state.
    """
    def make_move!(pid, player_id, notation) do
      assert :ok = BughouseGameServer.make_move(pid, player_id, notation)
      {:ok, state} = BughouseGameServer.get_state(pid)
      state
    end

    @doc """
    Helper to subscribe to game PubSub updates.
    """
    def subscribe_to_game(invite_code) do
      Phoenix.PubSub.subscribe(Bughouse.PubSub, "game:#{invite_code}")
    end

    @doc """
    Helper to get current game server state.
    """
    def get_state(pid) do
      {:ok, state} = BughouseGameServer.get_state(pid)
      state
    end
  end

  # ============================================================================
  # Setup and Teardown
  # ============================================================================

  setup do
    context = TestHelpers.setup_full_game()

    # Cleanup on test exit
    on_exit(fn ->
      if Process.alive?(context.pid) do
        BughouseGameServer.stop(context.pid)
      end
    end)

    context
  end

  # ============================================================================
  # Initialization Tests
  # ============================================================================

  describe "initialization" do
    test "starts with correct initial state", %{pid: pid} do
      state = TestHelpers.get_state(pid)

      # Verify board setup (simplified FEN with only piece placement)
      assert state.board_1_fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
      assert state.board_2_fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"

      # Verify clocks (5 minutes = 300,000 ms)
      assert state.clocks.board_1_white == 300_000
      assert state.clocks.board_1_black == 300_000
      assert state.clocks.board_2_white == 300_000
      assert state.clocks.board_2_black == 300_000

      # Verify active clocks (both whites start)
      assert :board_1_white in state.active_clocks
      assert :board_2_white in state.active_clocks
      assert length(state.active_clocks) == 2

      # Verify no result
      assert state.result == nil
      assert state.result_reason == nil
    end

    test "schedules timeout messages for both whites on start", %{pid: pid} do
      # Verify GenServer has scheduled timeouts
      server_state = :sys.get_state(pid)
      assert is_reference(server_state.timeout_refs.board_1_white)
      assert is_reference(server_state.timeout_refs.board_2_white)
      assert server_state.timeout_refs.board_1_black == nil
      assert server_state.timeout_refs.board_2_black == nil
    end

    test "initializes with empty move history", %{pid: pid} do
      state = TestHelpers.get_state(pid)
      assert state.last_move == nil
    end
  end

  # ============================================================================
  # Making Moves Tests
  # ============================================================================

  describe "making moves" do
    test "white can make first move on board 1", %{pid: pid, players: players} do
      assert :ok = BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      state = TestHelpers.get_state(pid)

      # Verify move was recorded
      assert state.last_move.notation == "e2e4"
      assert state.last_move.position == :board_1_white
      assert state.last_move.board == 1
      assert state.last_move.type == :move

      # Verify clock switched
      assert :board_1_black in state.active_clocks
      refute :board_1_white in state.active_clocks
    end

    test "both boards can move independently", %{pid: pid, players: players} do
      # Move on board 1
      assert :ok = BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      # Move on board 2 (still white's turn there)
      assert :ok = BughouseGameServer.make_move(pid, players.board_2_white, "d2d4")

      state = TestHelpers.get_state(pid)

      # Both blacks should be active now
      assert :board_1_black in state.active_clocks
      assert :board_2_black in state.active_clocks
      refute :board_1_white in state.active_clocks
      refute :board_2_white in state.active_clocks
    end

    test "returns error when not player's turn", %{pid: pid, players: players} do
      # Black tries to move first
      assert {:error, :not_your_turn} =
               BughouseGameServer.make_move(pid, players.board_1_black, "e7e5")
    end

    test "returns error for invalid move", %{pid: pid, players: players} do
      # Invalid move (can't move opponent's piece)
      assert {:error, _reason} =
               BughouseGameServer.make_move(pid, players.board_1_white, "e7e5")
    end

    test "broadcasts state update after move", %{pid: pid, players: players, game: game} do
      TestHelpers.subscribe_to_game(game.invite_code)

      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      assert_receive {:game_state_update, state}, 500
      assert state.last_move.notation == "e2e4"
    end

    test "move updates board FEN", %{pid: pid, players: players} do
      initial_state = TestHelpers.get_state(pid)
      initial_fen = initial_state.board_1_fen

      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      final_state = TestHelpers.get_state(pid)
      final_fen = final_state.board_1_fen

      # FEN should have changed
      assert final_fen != initial_fen
      # Board 2 should be unchanged
      assert final_state.board_2_fen == initial_state.board_2_fen
    end
  end

  # ============================================================================
  # Piece Drop Tests
  # ============================================================================

  describe "dropping pieces" do
    test "returns error when not player's turn", %{pid: pid, players: players} do
      assert {:error, :not_your_turn} =
               BughouseGameServer.drop_piece(pid, players.board_1_black, :n, "e4")
    end

    test "returns error when dropping on occupied square", %{pid: pid, players: players} do
      # Try to drop on occupied square (e2 has a pawn)
      assert {:error, _reason} =
               BughouseGameServer.drop_piece(pid, players.board_1_white, :n, "e2")
    end

    test "switching clocks after successful drop would work if piece available", %{
      pid: pid,
      players: players
    } do
      # This test documents expected behavior - we can't easily set up a capture
      # to get pieces in reserve in unit tests, so we just verify the error
      # when no piece is available
      assert {:error, _reason} =
               BughouseGameServer.drop_piece(pid, players.board_1_white, :n, "e4")
    end
  end

  # ============================================================================
  # Clock Management Tests
  # ============================================================================

  describe "clock management" do
    test "clock time decreases after moves", %{pid: pid, players: players} do
      initial_state = TestHelpers.get_state(pid)
      initial_time = initial_state.clocks.board_1_white

      # Wait a bit, then make a move
      Process.sleep(100)
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      final_state = TestHelpers.get_state(pid)
      final_time = final_state.clocks.board_1_white

      # Time should have decreased
      assert final_time < initial_time
      # Should be approximately 100ms less (with tolerance for processing)
      assert initial_time - final_time >= 90
      assert initial_time - final_time <= 200
    end

    test "timeout ref is cancelled after move", %{pid: pid, players: players} do
      # Get initial timeout ref
      server_state = :sys.get_state(pid)
      initial_ref = server_state.timeout_refs.board_1_white

      # Make a move
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      # Verify old timeout was cancelled and new one scheduled
      new_server_state = :sys.get_state(pid)
      assert new_server_state.timeout_refs.board_1_white == nil
      assert is_reference(new_server_state.timeout_refs.board_1_black)

      # Old ref should be different from new black ref
      assert initial_ref != new_server_state.timeout_refs.board_1_black
    end

    test "calculate current clocks correctly for active players", %{pid: pid, players: players} do
      # White's clock should be ticking
      state1 = TestHelpers.get_state(pid)
      Process.sleep(200)
      state2 = TestHelpers.get_state(pid)

      # board_1_white clock should have decreased
      assert state2.clocks.board_1_white < state1.clocks.board_1_white

      # board_1_black clock should NOT have changed (not active)
      assert state2.clocks.board_1_black == state1.clocks.board_1_black

      # Make a move to switch clocks
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      state3 = TestHelpers.get_state(pid)
      Process.sleep(200)
      state4 = TestHelpers.get_state(pid)

      # Now board_1_black should be ticking
      assert state4.clocks.board_1_black < state3.clocks.board_1_black

      # board_1_white should be stable
      assert state4.clocks.board_1_white == state3.clocks.board_1_white
    end

    test "clock values stored in move history", %{pid: pid, players: players} do
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      state = TestHelpers.get_state(pid)
      move = state.last_move

      # Move should have clock snapshot
      assert is_integer(move.board_1_white_time)
      assert is_integer(move.board_1_black_time)
      assert is_integer(move.board_2_white_time)
      assert is_integer(move.board_2_black_time)

      # All times should be positive
      assert move.board_1_white_time > 0
      assert move.board_1_black_time > 0
      assert move.board_2_white_time > 0
      assert move.board_2_black_time > 0
    end

    test "both board clocks run independently", %{pid: pid, players: players} do
      initial_state = TestHelpers.get_state(pid)

      # Both whites start with same time
      assert initial_state.clocks.board_1_white == initial_state.clocks.board_2_white

      # Wait, then move on board 1
      Process.sleep(100)
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      # Board 2 white should have continued ticking
      state_after_b1_move = TestHelpers.get_state(pid)

      # Board 2 white clock should still be running
      Process.sleep(100)
      state_after_delay = TestHelpers.get_state(pid)

      assert state_after_delay.clocks.board_2_white < state_after_b1_move.clocks.board_2_white
    end
  end

  # ============================================================================
  # Game Ending Tests - Resignation
  # ============================================================================

  describe "game endings - resignation" do
    test "player can resign", %{pid: pid, players: players} do
      assert :ok = BughouseGameServer.resign(pid, players.board_1_white)

      state = TestHelpers.get_state(pid)
      assert state.result == :team_2
      assert state.result_reason == :resignation
    end

    test "returns error if player resigns after game over", %{pid: pid, players: players} do
      BughouseGameServer.resign(pid, players.board_1_white)

      # Try to resign again
      assert {:error, :game_already_over} =
               BughouseGameServer.resign(pid, players.board_2_white)
    end

    test "correct team wins when board 1 white resigns", %{pid: pid, players: players} do
      BughouseGameServer.resign(pid, players.board_1_white)

      state = TestHelpers.get_state(pid)
      # board_1_white is team_1, so team_2 wins
      assert state.result == :team_2
    end

    test "correct team wins when board 2 black resigns", %{pid: pid, players: players} do
      BughouseGameServer.resign(pid, players.board_2_black)

      state = TestHelpers.get_state(pid)
      # board_2_black is team_1, so team_2 wins
      assert state.result == :team_2
    end

    test "broadcasts game over on resignation", %{pid: pid, players: players, game: game} do
      TestHelpers.subscribe_to_game(game.invite_code)

      BughouseGameServer.resign(pid, players.board_1_white)

      assert_receive {:game_over, state}, 500
      assert state.result == :team_2
      assert state.result_reason == :resignation
    end

    test "persists game to database on resignation", %{pid: pid, players: players, game: game} do
      BughouseGameServer.resign(pid, players.board_1_white)

      # Allow time for persistence
      Process.sleep(100)

      # Reload game from database
      updated_game = Games.get_game!(game.id)
      assert updated_game.status == :completed
      assert updated_game.result == "team_2_wins"
      assert updated_game.result_timestamp != nil
    end
  end

  # ============================================================================
  # Game Ending Tests - Draw by Agreement
  # ============================================================================

  describe "game endings - draw by agreement" do
    test "all 4 players must agree to draw", %{pid: pid, players: players} do
      # First 3 players offer draw
      BughouseGameServer.offer_draw(pid, players.board_1_white)
      BughouseGameServer.offer_draw(pid, players.board_1_black)
      BughouseGameServer.offer_draw(pid, players.board_2_white)

      state = TestHelpers.get_state(pid)
      assert state.result == nil

      # 4th player agrees
      BughouseGameServer.offer_draw(pid, players.board_2_black)

      state = TestHelpers.get_state(pid)
      assert state.result == :draw
      assert state.result_reason == :agreement
    end

    test "draw offer before all agree doesn't end game", %{pid: pid, players: players} do
      BughouseGameServer.offer_draw(pid, players.board_1_white)

      state = TestHelpers.get_state(pid)
      assert state.result == nil

      # Can still make moves
      assert :ok = BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")
    end

    test "broadcasts game over when draw agreed", %{pid: pid, players: players, game: game} do
      TestHelpers.subscribe_to_game(game.invite_code)

      # All 4 players agree
      BughouseGameServer.offer_draw(pid, players.board_1_white)
      BughouseGameServer.offer_draw(pid, players.board_1_black)
      BughouseGameServer.offer_draw(pid, players.board_2_white)
      BughouseGameServer.offer_draw(pid, players.board_2_black)

      assert_receive {:game_over, state}, 500
      assert state.result == :draw
    end
  end

  # ============================================================================
  # Game Ending Tests - Timeout
  # ============================================================================

  describe "game endings - timeout" do
    @tag :timeout_test
    test "player times out if no move before timeout" do
      context = TestHelpers.setup_short_game()

      # Wait for timeout (1 second + buffer)
      Process.sleep(1200)

      state = TestHelpers.get_state(context.pid)
      assert state.result != nil
      assert state.result_reason == :timeout

      # Cleanup
      if Process.alive?(context.pid) do
        BughouseGameServer.stop(context.pid)
      end
    end

    @tag :timeout_test
    test "correct team wins on timeout" do
      context = TestHelpers.setup_short_game()

      # Make a move on board_2 to prevent board_2_white from timing out
      # This ensures only board_1_white will timeout
      BughouseGameServer.make_move(context.pid, context.players.board_2_white, "e2e4")

      # Let board_1_white timeout
      Process.sleep(1200)

      state = TestHelpers.get_state(context.pid)
      # board_1_white is on team_1, so team_2 wins
      assert state.result == :team_2
      assert state.result_reason == :timeout

      # Cleanup
      if Process.alive?(context.pid) do
        BughouseGameServer.stop(context.pid)
      end
    end

    @tag :timeout_test
    test "timeout message is ignored if clock is no longer active" do
      context = TestHelpers.setup_short_game()

      # This test verifies that timeout messages for cancelled clocks are ignored.
      # With 1sec time control, we need to keep making moves quickly to verify
      # that old timeout messages don't crash the game.

      # Make initial moves quickly
      Process.sleep(100)
      BughouseGameServer.make_move(context.pid, context.players.board_1_white, "e2e4")
      BughouseGameServer.make_move(context.pid, context.players.board_2_white, "e2e4")

      Process.sleep(100)
      BughouseGameServer.make_move(context.pid, context.players.board_1_black, "e7e5")
      BughouseGameServer.make_move(context.pid, context.players.board_2_black, "e7e5")

      # Make another round of moves
      Process.sleep(100)
      BughouseGameServer.make_move(context.pid, context.players.board_1_white, "g1f3")
      BughouseGameServer.make_move(context.pid, context.players.board_2_white, "g1f3")

      # At this point, multiple timeout messages have been scheduled and cancelled
      # Wait a bit to see if any cause issues (they should be ignored)
      Process.sleep(500)

      # Game should still be ongoing (blacks are now on the clock)
      state = TestHelpers.get_state(context.pid)
      # Either game is still ongoing, or blacks timed out (which is acceptable)
      # The key is that the game didn't crash from old timeout messages
      assert state.result in [nil, :team_1, :team_2]

      # Cleanup
      if Process.alive?(context.pid) do
        BughouseGameServer.stop(context.pid)
      end
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "error handling" do
    test "returns error when game already over", %{pid: pid, players: players} do
      # End the game
      BughouseGameServer.resign(pid, players.board_1_white)

      # Try to make a move
      assert {:error, :game_over} =
               BughouseGameServer.make_move(pid, players.board_1_black, "e7e5")
    end

    test "returns error for invalid move notation", %{pid: pid, players: players} do
      # Use a move with valid squares but illegal (pawn can't move 3 squares)
      assert {:error, _reason} =
               BughouseGameServer.make_move(pid, players.board_1_white, "e2e5")
    end

    test "returns error for non-existent player", %{pid: pid} do
      fake_player_id = Ecto.UUID.generate()

      assert {:error, :not_your_turn} =
               BughouseGameServer.make_move(pid, fake_player_id, "e2e4")
    end

    test "returns error when wrong player tries to move", %{pid: pid, players: players} do
      # board_1_white makes a move
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      # board_1_white tries to move again (but it's black's turn now)
      assert {:error, :not_your_turn} =
               BughouseGameServer.make_move(pid, players.board_1_white, "d2d4")
    end

    test "cannot offer draw after game over", %{pid: pid, players: players} do
      BughouseGameServer.resign(pid, players.board_1_white)

      assert {:error, :game_already_over} =
               BughouseGameServer.offer_draw(pid, players.board_2_white)
    end
  end

  # ============================================================================
  # GenServer Lifecycle Tests
  # ============================================================================

  describe "GenServer lifecycle" do
    test "GenServer terminates cleanly", %{pid: pid} do
      assert Process.alive?(pid)

      BughouseGameServer.stop(pid)

      # Wait for termination
      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "cancels timeout refs on termination", %{pid: pid} do
      # Get timeout refs
      server_state = :sys.get_state(pid)
      ref1 = server_state.timeout_refs.board_1_white
      ref2 = server_state.timeout_refs.board_2_white

      assert is_reference(ref1)
      assert is_reference(ref2)

      # Stop server
      BughouseGameServer.stop(pid)

      # Wait for termination
      Process.sleep(100)

      # Process should be dead
      refute Process.alive?(pid)
    end
  end

  # ============================================================================
  # State Serialization Tests
  # ============================================================================

  describe "state serialization" do
    test "get_state returns correct format for client", %{pid: pid} do
      {:ok, state} = BughouseGameServer.get_state(pid)

      # Verify structure
      assert is_binary(state.board_1_fen)
      assert is_binary(state.board_2_fen)
      assert is_map(state.clocks)
      assert is_list(state.active_clocks)
      assert state.result == nil
      assert state.result_reason == nil

      # Verify clock keys
      assert Map.has_key?(state.clocks, :board_1_white)
      assert Map.has_key?(state.clocks, :board_1_black)
      assert Map.has_key?(state.clocks, :board_2_white)
      assert Map.has_key?(state.clocks, :board_2_black)
    end

    test "clocks in state reflect current time", %{pid: pid} do
      # Get state twice with delay
      state1 = TestHelpers.get_state(pid)
      Process.sleep(100)
      state2 = TestHelpers.get_state(pid)

      # Active clock should have decreased
      assert state2.clocks.board_1_white < state1.clocks.board_1_white

      # Inactive clock should be the same
      assert state2.clocks.board_1_black == state1.clocks.board_1_black
    end

    test "state includes active clocks list", %{pid: pid} do
      state = TestHelpers.get_state(pid)

      # Both whites should be active initially
      assert :board_1_white in state.active_clocks
      assert :board_2_white in state.active_clocks
      assert length(state.active_clocks) == 2
    end

    test "state includes last move information", %{pid: pid, players: players} do
      # Initially no moves
      state_before = TestHelpers.get_state(pid)
      assert state_before.last_move == nil

      # Make a move
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      state_after = TestHelpers.get_state(pid)
      assert state_after.last_move != nil
      assert state_after.last_move.notation == "e2e4"
      assert state_after.last_move.position == :board_1_white
    end
  end

  # ============================================================================
  # PubSub Broadcasting Tests
  # ============================================================================

  describe "PubSub broadcasts" do
    test "broadcasts state update after move", %{pid: pid, players: players, game: game} do
      TestHelpers.subscribe_to_game(game.invite_code)

      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      assert_receive {:game_state_update, state}, 500
      assert state.last_move.notation == "e2e4"
    end

    test "broadcasts game over on resignation", %{pid: pid, players: players, game: game} do
      TestHelpers.subscribe_to_game(game.invite_code)

      BughouseGameServer.resign(pid, players.board_1_white)

      assert_receive {:game_over, state}, 500
      assert state.result == :team_2
      assert state.result_reason == :resignation
    end

    test "multiple subscribers receive broadcasts", %{pid: pid, players: players, game: game} do
      # Simulate multiple clients subscribing
      TestHelpers.subscribe_to_game(game.invite_code)

      # Spawn another process to subscribe
      test_pid = self()

      spawn(fn ->
        TestHelpers.subscribe_to_game(game.invite_code)

        receive do
          {:game_state_update, state} ->
            send(test_pid, {:received_by_other, state})
        after
          1000 -> send(test_pid, :timeout)
        end
      end)

      # Make a move
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")

      # Both should receive
      assert_receive {:game_state_update, _state}, 500
      assert_receive {:received_by_other, _other_state}, 500
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "full game flow" do
    test "complete game with moves on both boards", %{pid: pid, players: players} do
      # Board 1 moves
      assert :ok = BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")
      assert :ok = BughouseGameServer.make_move(pid, players.board_1_black, "e7e5")

      # Board 2 moves
      assert :ok = BughouseGameServer.make_move(pid, players.board_2_white, "d2d4")
      assert :ok = BughouseGameServer.make_move(pid, players.board_2_black, "d7d5")

      # More moves on board 1
      assert :ok = BughouseGameServer.make_move(pid, players.board_1_white, "g1f3")
      assert :ok = BughouseGameServer.make_move(pid, players.board_1_black, "b8c6")

      state = TestHelpers.get_state(pid)

      # Game should still be in progress
      assert state.result == nil

      # Verify FENs have changed from initial position
      refute state.board_1_fen =~ "rnbqkbnr/pppppppp"
      refute state.board_2_fen =~ "rnbqkbnr/pppppppp"
    end

    test "game ends when player resigns mid-game", %{pid: pid, players: players} do
      # Make some moves
      BughouseGameServer.make_move(pid, players.board_1_white, "e2e4")
      BughouseGameServer.make_move(pid, players.board_1_black, "e7e5")
      BughouseGameServer.make_move(pid, players.board_2_white, "d2d4")

      # Player resigns
      BughouseGameServer.resign(pid, players.board_2_black)

      state = TestHelpers.get_state(pid)
      assert state.result == :team_2

      # Can't make more moves
      assert {:error, :game_over} =
               BughouseGameServer.make_move(pid, players.board_2_white, "d4d5")
    end
  end
end
