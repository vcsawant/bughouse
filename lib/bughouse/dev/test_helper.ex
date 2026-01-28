defmodule Bughouse.Dev.TestHelper do
  @moduledoc """
  Helper functions for testing BughouseGameServer in IEx.

  ## Quick Start

      iex> alias Bughouse.Dev.TestHelper, as: T
      iex> {:ok, game, pid} = T.setup_game()
      iex> T.show(pid)
      iex> T.move(pid, 1, "e2e4")
      iex> T.move(pid, 2, "e7e5")
      iex> T.show(pid)

  ## Available Functions

  - `setup_game/0` - Create game with 4 players and start server
  - `show/1` - Pretty-print full game state
  - `quick/1` - Show just clocks and active players
  - `move/3` - Make a move (player number 1-4, notation)
  - `drop/4` - Drop a piece (player number, piece atom, square)
  - `resign/2` - Player resigns
  - `wait/1` - Wait N seconds (to see clock tick)
  - `cleanup/1` - Stop the game server
  """

  alias Bughouse.{Games, Accounts}
  alias Bughouse.Dev.GamePrinter

  @doc """
  Sets up a complete game with 4 players and returns {game, pid, players}.

  Returns:
    {:ok, game, pid, %{p1: player1, p2: player2, p3: player3, p4: player4}}
  """
  def setup_game do
    # Create 4 guest players
    {:ok, p1} = Accounts.create_guest_player()
    {:ok, p2} = Accounts.create_guest_player()
    {:ok, p3} = Accounts.create_guest_player()
    {:ok, p4} = Accounts.create_guest_player()

    # Create game
    {:ok, game} = Games.create_game(%{time_control: "5min"})

    # Join all players
    {:ok, _} = Games.join_game(game.id, p1.id, :board_1_white)
    {:ok, _} = Games.join_game(game.id, p2.id, :board_1_black)
    {:ok, _} = Games.join_game(game.id, p3.id, :board_2_white)
    {:ok, _} = Games.join_game(game.id, p4.id, :board_2_black)

    # Start the game
    {:ok, game, pid} = Games.start_game(game.id)

    players = %{
      # board_1_white - Team 1
      p1: p1,
      # board_1_black - Team 2
      p2: p2,
      # board_2_white - Team 2
      p3: p3,
      # board_2_black - Team 1
      p4: p4
    }

    IO.puts("\n✅ Game #{game.invite_code} created!")
    IO.puts("   Players:")
    IO.puts("   - P1 (#{p1.display_name}): board_1_white - Team 1")
    IO.puts("   - P2 (#{p2.display_name}): board_1_black - Team 2")
    IO.puts("   - P3 (#{p3.display_name}): board_2_white - Team 2")
    IO.puts("   - P4 (#{p4.display_name}): board_2_black - Team 1")
    IO.puts("   PID: #{inspect(pid)}\n")

    {:ok, game, pid, players}
  end

  @doc """
  Pretty-print full game state.
  """
  def show(pid) do
    GamePrinter.print_game_state(pid)
  end

  @doc """
  Quick view of clocks and active players.
  """
  def quick(pid) do
    GamePrinter.print_quick_state(pid)
  end

  @doc """
  Make a move for a player.

  ## Examples

      move(pid, 1, "e2e4")  # Player 1 (board_1_white) moves
      move(pid, 2, "e7e5")  # Player 2 (board_1_black) moves
  """
  def move(pid, player_num, notation) when player_num in 1..4 do
    state = :sys.get_state(pid)
    player_id = get_player_id(state, player_num)

    case Bughouse.Games.BughouseGameServer.make_move(pid, player_id, notation) do
      :ok ->
        IO.puts("✓ Player #{player_num} moved: #{notation}")
        quick(pid)
        :ok

      {:error, reason} ->
        IO.puts("✗ Move failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Drop a piece from reserves.

  ## Examples

      drop(pid, 1, :p, "e4")  # Player 1 drops pawn on e4
      drop(pid, 4, :n, "f3")  # Player 4 drops knight on f3
  """
  def drop(pid, player_num, piece_type, square) when player_num in 1..4 do
    state = :sys.get_state(pid)
    player_id = get_player_id(state, player_num)

    case Bughouse.Games.BughouseGameServer.drop_piece(pid, player_id, piece_type, square) do
      :ok ->
        IO.puts("✓ Player #{player_num} dropped #{piece_type} on #{square}")
        quick(pid)
        :ok

      {:error, reason} ->
        IO.puts("✗ Drop failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Player resigns.
  """
  def resign(pid, player_num) when player_num in 1..4 do
    state = :sys.get_state(pid)
    player_id = get_player_id(state, player_num)

    case Bughouse.Games.BughouseGameServer.resign(pid, player_id) do
      :ok ->
        IO.puts("✓ Player #{player_num} resigned")
        show(pid)
        :ok

      {:error, reason} ->
        IO.puts("✗ Resign failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Wait for N seconds (to watch clock tick).
  """
  def wait(seconds) do
    IO.puts("⏳ Waiting #{seconds} seconds...")
    Process.sleep(seconds * 1000)
    IO.puts("✓ Done waiting")
  end

  @doc """
  Stop the game server.
  """
  def cleanup(pid) do
    Bughouse.Games.BughouseGameServer.stop(pid)
    IO.puts("✓ Game server stopped")
  end

  @doc """
  Run a quick test scenario.
  """
  def quick_test do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("QUICK TEST SCENARIO")
    IO.puts(String.duplicate("=", 80) <> "\n")

    {:ok, _game, pid, _players} = setup_game()

    IO.puts("\n📍 Initial state:")
    show(pid)

    IO.puts("\n📍 Making some moves on both boards...")
    # board_1_white
    move(pid, 1, "e2e4")
    # board_1_black
    move(pid, 2, "e7e5")
    # board_2_white
    move(pid, 3, "d2d4")
    # board_2_black
    move(pid, 4, "d7d5")

    IO.puts("\n📍 A few more moves...")
    # board_1_white
    move(pid, 1, "g1f3")
    # board_1_black
    move(pid, 2, "b8c6")

    IO.puts("\n📍 Final state after moves:")
    show(pid)

    IO.puts("\n📍 Waiting 2 seconds to see clocks tick...")
    wait(2)
    quick(pid)

    cleanup(pid)

    IO.puts("\n✅ Quick test complete!")
  end

  @doc """
  Test capture and reserve transfer.
  """
  def test_capture do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("CAPTURE & RESERVE TEST")
    IO.puts(String.duplicate("=", 80) <> "\n")

    {:ok, _game, pid, _players} = setup_game()

    IO.puts("\n📍 Setting up capture scenario...")
    # board_1_white
    move(pid, 1, "e2e4")
    # board_1_black
    move(pid, 2, "d7d5")
    # board_2_white
    move(pid, 3, "e2e4")
    # board_2_black
    move(pid, 4, "d7d5")

    IO.puts("\n📍 Board 1: White captures black pawn...")
    # Capture!
    move(pid, 1, "e4d5")

    IO.puts("\n📍 State after capture (check reserves):")
    show(pid)

    IO.puts("\n💡 Expected: Team 1 should have a pawn in reserves")
    IO.puts("   - Should appear in Board 2's black reserves")
    IO.puts("   - Player 4 (board_2_black - Team 1) can drop it")

    cleanup(pid)

    IO.puts("\n✅ Capture test complete!")
  end

  ## Private Helpers

  defp get_player_id(state, 1), do: state.board_1_white_id
  defp get_player_id(state, 2), do: state.board_1_black_id
  defp get_player_id(state, 3), do: state.board_2_white_id
  defp get_player_id(state, 4), do: state.board_2_black_id
end
