defmodule Bughouse.BotEngine.Server do
  @moduledoc """
  GenServer that owns an Erlang Port to the bughouse-engine Rust binary.

  Subscribes to game PubSub as an independent observer (same pattern as GameLive).
  When it's the bot's turn, it fetches full BFEN from the GameServer, sends UBI
  commands to the engine, and plays the returned `bestmove` via the Games API.

  One instance per bot per game — a dual bot (both team seats) is still one process.
  """
  use GenServer
  require Logger

  alias Bughouse.Games
  alias Bughouse.TeamComm

  defstruct [
    :port,
    :game_id,
    :invite_code,
    :bot_player_id,
    :bot_team,
    :positions,
    :engine_ready,
    :pending_go,
    :line_buffer
  ]

  ## Public API

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  ## GenServer Callbacks

  @impl true
  def init(%{
        game_id: game_id,
        invite_code: invite_code,
        bot_player_id: bot_player_id,
        positions: positions
      }) do
    # Subscribe to game PubSub — same topic as GameLive
    Games.subscribe_to_game(invite_code)

    # Subscribe to team-scoped topic for teammate communication
    bot_team = TeamComm.team_for_positions(positions)

    if bot_team do
      TeamComm.subscribe(invite_code, bot_team)
    end

    # Open Port to the engine binary
    engine_path = get_engine_path()
    engine_args = build_engine_args(game_id)

    port =
      Port.open({:spawn_executable, engine_path}, [
        {:args, engine_args},
        :binary,
        {:line, 4096},
        :use_stdio,
        :exit_status
      ])

    state = %__MODULE__{
      port: port,
      game_id: game_id,
      invite_code: invite_code,
      bot_player_id: bot_player_id,
      bot_team: bot_team,
      positions: MapSet.new(positions),
      engine_ready: false,
      pending_go: nil,
      line_buffer: ""
    }

    # Start UBI handshake
    send_to_engine(port, "ubi")

    Logger.info(
      "BotEngineServer started for game #{invite_code}, " <>
        "bot #{bot_player_id}, positions: #{inspect(positions)}"
    )

    {:ok, state}
  end

  # Port data — engine sends lines back via stdout
  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    state = handle_engine_line(String.trim(line), state)
    {:noreply, state}
  end

  # Partial line (no newline yet) — buffer it
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | line_buffer: state.line_buffer <> chunk}}
  end

  # Game state update from PubSub
  def handle_info({:game_state_update, game_state}, state) do
    state = maybe_request_move(state, game_state)
    {:noreply, state}
  end

  # Game over from PubSub
  def handle_info({:game_over, _game_state}, state) do
    Logger.info("BotEngineServer: game #{state.invite_code} over, shutting down")
    send_to_engine(state.port, "quit")
    {:stop, :normal, state}
  end

  # Game started broadcast (ignore — we're already initialized)
  def handle_info({:game_started, _game}, state) do
    {:noreply, state}
  end

  # Player joined/left broadcasts (ignore — game is already in progress)
  def handle_info({:player_joined, _game}, state) do
    {:noreply, state}
  end

  def handle_info({:player_left, _game}, state) do
    {:noreply, state}
  end

  # Team communication from human teammate — forward as UBI partnermsg to engine
  def handle_info({:team_message, message}, state) do
    if message.from_player_id != state.bot_player_id and state.port != nil do
      ubi_line = TeamComm.to_ubi_partnermsg(message)
      send_to_engine(state.port, ubi_line)
    end

    {:noreply, state}
  end

  # Port exited
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning(
      "BotEngineServer: engine exited with code #{code} for game #{state.invite_code}"
    )

    {:stop, :normal, %{state | port: nil}}
  end

  @impl true
  def terminate(_reason, %{port: nil}), do: :ok

  def terminate(_reason, state) do
    send_to_engine(state.port, "quit")

    # Give the engine a moment to exit cleanly
    receive do
      {port, {:exit_status, _}} when port == state.port -> :ok
    after
      500 -> Port.close(state.port)
    end

    :ok
  end

  ## Engine Line Handling (UBI protocol)

  defp handle_engine_line("", state), do: state

  defp handle_engine_line("ubiok", state) do
    # Handshake complete — set up new game and check readiness
    send_to_engine(state.port, "ubinewgame")
    send_to_engine(state.port, "isready")
    state
  end

  defp handle_engine_line("readyok", state) do
    Logger.debug("BotEngineServer: engine ready for game #{state.invite_code}")
    state = %{state | engine_ready: true}

    # Check if it's already the bot's turn (e.g. bot plays white at game start)
    check_and_request_move(state)
  end

  defp handle_engine_line("bestmove board " <> rest, state) do
    handle_bestmove(rest, state)
  end

  defp handle_engine_line("id " <> _rest, state) do
    # Engine identification — ignore
    state
  end

  defp handle_engine_line("info " <> _rest, state) do
    # Search info — ignore for now (could log in debug)
    state
  end

  defp handle_engine_line("teammsg " <> _rest = line, state) do
    # Engine wants to communicate with its human teammate
    if state.bot_team do
      bot_position = get_bot_active_position(state)

      case TeamComm.parse_engine_teammsg(line, state.bot_player_id, bot_position) do
        {:ok, message} ->
          TeamComm.broadcast(state.invite_code, state.bot_team, message)

        {:error, _} ->
          Logger.debug("BotEngineServer: failed to parse teammsg: #{inspect(line)}")
      end
    end

    state
  end

  defp handle_engine_line(line, state) do
    Logger.debug("BotEngineServer: unhandled engine line: #{inspect(line)}")
    state
  end

  ## Move Request Logic

  defp maybe_request_move(state, _game_state) when not state.engine_ready do
    # Engine not ready yet, ignore
    state
  end

  defp maybe_request_move(state, _game_state) when state.pending_go != nil do
    # Engine is busy with a previous request, ignore
    state
  end

  defp maybe_request_move(state, game_state) do
    if game_state[:result] != nil do
      # Game is over
      state
    else
      active_clocks = game_state[:active_clocks] || []

      # Find the first of our positions that has an active clock
      case Enum.find(state.positions, fn pos -> pos in active_clocks end) do
        nil ->
          # Not our turn on any board
          state

        position ->
          request_move(state, position)
      end
    end
  end

  defp check_and_request_move(state) do
    # Fetch current game state to see if it's our turn
    case Games.get_game_state(state.game_id) do
      {:ok, game_state} ->
        maybe_request_move(state, game_state)

      {:error, _reason} ->
        # Game server might not be ready yet, that's fine
        state
    end
  end

  defp request_move(state, position) do
    case Games.get_bfen(state.game_id) do
      {:ok, board_1_bfen, board_2_bfen, clocks} ->
        # Send both board positions
        send_to_engine(state.port, "position board A bfen #{board_1_bfen}")
        send_to_engine(state.port, "position board B bfen #{board_2_bfen}")

        # Send clock values
        send_to_engine(
          state.port,
          "clock white_A #{round(clocks.board_1_white)}"
        )

        send_to_engine(
          state.port,
          "clock black_A #{round(clocks.board_1_black)}"
        )

        send_to_engine(
          state.port,
          "clock white_B #{round(clocks.board_2_white)}"
        )

        send_to_engine(
          state.port,
          "clock black_B #{round(clocks.board_2_black)}"
        )

        # Determine UBI board id from position
        board_id = position_to_ubi_board(position)
        send_to_engine(state.port, "go board #{board_id}")

        %{state | pending_go: position}

      {:error, reason} ->
        Logger.warning("BotEngineServer: failed to get BFEN: #{inspect(reason)}")
        state
    end
  end

  ## Best Move Handling

  defp handle_bestmove(rest, state) do
    # Parse "A e2e4" or "B p@e4"
    case String.split(rest, " ", parts: 2) do
      [_board_str, move_str] ->
        execute_move(state, move_str, state.pending_go)

      _ ->
        Logger.warning("BotEngineServer: malformed bestmove: #{inspect(rest)}")
        %{state | pending_go: nil}
    end
  end

  defp execute_move(state, move_str, position) do
    result =
      if drop_move?(move_str) do
        # Drop move: "p@e4" → piece_type :p, square "e4"
        {piece_char, "@" <> square} = String.split_at(move_str, 1)
        piece_type = String.to_atom(piece_char)
        Games.drop_game_piece(state.game_id, state.bot_player_id, piece_type, square, position)
      else
        # Regular move: "e2e4" or "e7e8q" (promotion)
        Games.make_game_move(state.game_id, state.bot_player_id, move_str, position)
      end

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "BotEngineServer: move #{move_str} rejected: #{inspect(reason)} " <>
            "(game #{state.invite_code})"
        )
    end

    # Clear pending_go — the resulting PubSub broadcast will trigger next move
    %{state | pending_go: nil}
  end

  ## Helpers

  defp send_to_engine(port, command) do
    Port.command(port, command <> "\n")
  end

  defp drop_move?(move_str) do
    byte_size(move_str) >= 3 and String.at(move_str, 1) == "@"
  end

  defp position_to_ubi_board(position) when position in [:board_1_white, :board_1_black], do: "A"
  defp position_to_ubi_board(position) when position in [:board_2_white, :board_2_black], do: "B"

  defp get_bot_active_position(state) do
    # Return the position the bot is currently thinking about, or the first position
    state.pending_go || Enum.at(MapSet.to_list(state.positions), 0)
  end

  defp get_engine_path do
    Application.get_env(:bughouse, :bot_engine)[:engine_path] ||
      raise "Bot engine path not configured. Set :bughouse, :bot_engine, :engine_path"
  end

  defp build_engine_args(game_id) do
    base_args = ["--game-id", game_id]

    case Application.get_env(:bughouse, :bot_engine)[:game_log_path] do
      nil ->
        base_args

      log_dir ->
        File.mkdir_p!(log_dir)
        timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
        log_file = Path.join(log_dir, "#{timestamp}_#{game_id}.log")
        base_args ++ ["--log-file", log_file]
    end
  end

  ## Child Spec

  def child_spec(args) do
    %{
      id: {__MODULE__, args.game_id, args.bot_player_id},
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary,
      type: :worker
    }
  end
end
