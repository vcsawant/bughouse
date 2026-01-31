defmodule Bughouse.Dev.GamePrinter do
  @moduledoc """
  Pretty-prints Bughouse game state for debugging and testing.
  """

  @doc """
  Prints a complete view of the game state including both boards, clocks, and reserves.
  """
  def print_game_state(game_server_pid) do
    {:ok, state} = Bughouse.Games.BughouseGameServer.get_state(game_server_pid)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("BUGHOUSE GAME STATE")
    IO.puts(String.duplicate("=", 80))

    print_clocks(state)
    print_boards(game_server_pid)
    print_reserves(state)
    print_active_players(state)
    print_game_status(state)

    IO.puts(String.duplicate("=", 80) <> "\n")
  end

  defp print_clocks(state) do
    IO.puts("\n⏱️  CLOCKS:")

    IO.puts(
      "  Board 1: White #{format_time(state.clocks.board_1_white)} | Black #{format_time(state.clocks.board_1_black)}"
    )

    IO.puts(
      "  Board 2: White #{format_time(state.clocks.board_2_white)} | Black #{format_time(state.clocks.board_2_black)}"
    )
  end

  defp print_boards(game_server_pid) do
    # Get the actual state struct to access board PIDs
    state = :sys.get_state(game_server_pid)

    IO.puts("\n♟️  BOARD 1 (Team 1 White vs Team 2 Black):")
    :binbo_bughouse.print_board(state.board_1_pid, [:unicode])

    IO.puts("\n♟️  BOARD 2 (Team 2 White vs Team 1 Black):")
    :binbo_bughouse.print_board(state.board_2_pid, [:unicode])
  end

  defp print_reserves(state) do
    {:ok, board_1_fen} = parse_fen_reserves(state.board_1_fen)
    {:ok, board_2_fen} = parse_fen_reserves(state.board_2_fen)

    IO.puts("\n📦 RESERVES:")

    IO.puts(
      "  Board 1 - White: #{inspect(board_1_fen.white_reserves)} | Black: #{inspect(board_1_fen.black_reserves)}"
    )

    IO.puts(
      "  Board 2 - White: #{inspect(board_2_fen.white_reserves)} | Black: #{inspect(board_2_fen.black_reserves)}"
    )

    IO.puts("\n  🏳️  Team 1 (board_1_white + board_2_black) reserves:")
    IO.puts("     - Can drop on Board 1 as WHITE: #{inspect(board_1_fen.white_reserves)}")
    IO.puts("     - Can drop on Board 2 as BLACK: #{inspect(board_2_fen.black_reserves)}")
    IO.puts("  🏴 Team 2 (board_1_black + board_2_white) reserves:")
    IO.puts("     - Can drop on Board 1 as BLACK: #{inspect(board_1_fen.black_reserves)}")
    IO.puts("     - Can drop on Board 2 as WHITE: #{inspect(board_2_fen.white_reserves)}")
  end

  defp print_active_players(state) do
    active = state.active_clocks |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")
    IO.puts("\n👤 ACTIVE (whose turn): #{active}")
  end

  defp print_game_status(state) do
    if state.result do
      IO.puts("\n🏁 GAME OVER: #{state.result} (#{state.result_reason})")
    else
      IO.puts("\n▶️  GAME IN PROGRESS")
    end
  end

  defp format_time(ms) when ms <= 0, do: "0:00.0 ⏰"

  defp format_time(ms) do
    total_seconds = div(ms, 1000)
    deciseconds = div(rem(ms, 1000), 100)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    "#{minutes}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}.#{deciseconds}"
  end

  defp parse_fen_reserves(fen_string) do
    # Extract reserves from binbo_bughouse FEN format
    # Format: "rnbqkbnr/.../RNBQKBNR[PNp] w KQkq - 0 1"
    # Uppercase = white pieces, lowercase = black pieces
    case Regex.run(~r/\[([PNBRQpnbrq]*)\]/, fen_string) do
      [_, reserve_str] ->
        {white_pieces, black_pieces} =
          reserve_str
          |> String.graphemes()
          |> Enum.split_with(fn char -> char == String.upcase(char) end)

        {:ok,
         %{
           white_reserves: parse_reserve_string(Enum.join(white_pieces)),
           black_reserves: parse_reserve_string(Enum.join(black_pieces))
         }}

      nil ->
        {:ok, %{white_reserves: %{}, black_reserves: %{}}}
    end
  end

  defp parse_reserve_string(""), do: %{}

  defp parse_reserve_string(str) do
    str
    |> String.graphemes()
    |> Enum.frequencies()
    |> Map.new(fn {char, count} -> {String.downcase(char) |> String.to_atom(), count} end)
  end

  @doc """
  Prints a simplified view showing just clocks and whose turn.
  """
  def print_quick_state(game_server_pid) do
    {:ok, state} = Bughouse.Games.BughouseGameServer.get_state(game_server_pid)

    active = state.active_clocks |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")

    IO.puts(
      "⏱️  B1: W #{format_time(state.clocks.board_1_white)} | B #{format_time(state.clocks.board_1_black)}  " <>
        "B2: W #{format_time(state.clocks.board_2_white)} | B #{format_time(state.clocks.board_2_black)}  " <>
        "👤 #{active}"
    )
  end

  @doc """
  Prints move history.
  """
  def print_move_history(game_server_pid, _limit \\ 10) do
    {:ok, state} = Bughouse.Games.BughouseGameServer.get_state(game_server_pid)

    if state.last_move do
      IO.puts("\n📜 LAST MOVE:")
      move = state.last_move
      IO.puts("  Board #{move.board}: #{move.position} - #{move.type} #{move.notation}")
      IO.puts("  Timestamp: #{move.timestamp}")
    else
      IO.puts("\n📜 No moves yet")
    end
  end
end
