defmodule BughouseWeb.GameLive do
  @moduledoc """
  Live view for the real-time Bughouse chess game interface.

  This module handles the main game view where four players see two side-by-side
  boards with their clocks and reserve pieces. Players can make moves, drop pieces,
  and see real-time updates from all players via Phoenix PubSub.

  ## Layout

  - Team 2's players displayed at top (board_1_black, board_2_white)
  - Team 1's players displayed at bottom (board_1_white, board_2_black)
  - Clocks and reserves positioned above/below boards respectively
  - Each player sees their own board pieces at the bottom (flipped orientation)

  ## Socket Assigns

  - `invite_code` - Game invite code from URL
  - `game` - Game schema (player IDs, status, etc.)
  - `game_state` - Real-time state from BughouseGameServer (FENs, clocks, reserves)
  - `players` - Map of player_id => player_name
  - `my_position` - Current player's position (:board_1_white, :board_1_black, etc. or nil for spectator)
  - `my_team` - Current player's team (:team_1, :team_2, or nil)
  - `selected_square` - Currently selected square notation (e.g., "e2")
  - `selected_reserve_piece` - Currently selected reserve piece type (e.g., :p, :n, etc.)
  - `highlighted_squares` - List of valid move/drop destinations
  """
  use BughouseWeb, :live_view
  alias Bughouse.Games

  @impl true
  def mount(%{"invite_code" => code}, _session, socket) do
    require Logger
    current_player = socket.assigns.current_player

    Logger.info(
      "GameLive mount: player=#{current_player.id} (#{current_player.display_name}), code=#{code}"
    )

    case Games.get_game_by_invite_code(code) do
      nil ->
        Logger.warning("GameLive: Game not found for code=#{code}, player=#{current_player.id}")

        {:ok,
         socket
         |> put_flash(:error, "Game not found")
         |> redirect(to: ~p"/")}

      game ->
        if connected?(socket) do
          Games.subscribe_to_game(code)
          Logger.debug("GameLive: Subscribed to game:#{code}")
        end

        # Get real-time game state from server
        {:ok, game_state} = Games.get_game_state(game.id)

        # Get player names
        {_game, players} = Games.get_game_with_players(code)

        my_position = find_my_position(game, current_player.id)

        Logger.info(
          "GameLive: Loaded game #{game.id}, my_position=#{inspect(my_position)}, status=#{game.status}"
        )

        {:ok,
         socket
         |> assign(:invite_code, code)
         |> assign(:game, game)
         |> assign(:game_state, game_state)
         |> assign(:players, players)
         |> assign(:my_position, my_position)
         |> assign(:my_team, get_my_team(my_position))
         |> assign(:selected_square, nil)
         |> assign(:selected_reserve_piece, nil)
         |> assign(:highlighted_squares, [])}
    end
  end

  @impl true
  def handle_event("select_square", %{"square" => square, "board" => board_str}, socket) do
    board_num = String.to_integer(board_str)
    my_position = socket.assigns.my_position

    # Spectators can't interact
    if my_position == nil do
      {:noreply, socket}
    else
      my_board = get_position_board(my_position)

      # Check if this is my board
      if board_num != my_board do
        {:noreply, socket}
      else
        # If a reserve piece is selected, this is a drop attempt
        if socket.assigns.selected_reserve_piece do
          handle_drop_attempt(socket, socket.assigns.selected_reserve_piece, square)
        # If a square is already selected, this is a move attempt
        else
          if socket.assigns.selected_square do
            handle_move_attempt(socket, socket.assigns.selected_square, square)
          else
            # Validate piece selection with game server
            player_id = socket.assigns.current_player.id

            case Games.can_select_piece?(socket.assigns.game.id, player_id, square) do
              :ok ->
                # Valid piece - select it
                # TODO: Get valid moves from server and set highlighted_squares
                {:noreply, assign(socket, selected_square: square, highlighted_squares: [])}

              {:error, _reason} ->
                # Invalid selection (empty square, opponent's piece, or not player's turn)
                # Silently ignore - don't select anything
                {:noreply, socket}
            end
          end
        end
      end
    end
  end

  @impl true
  def handle_event("select_reserve_piece", %{"piece" => piece}, socket) do
    # Toggle selection: if clicking the same piece, deselect
    piece_atom = String.to_atom(piece)

    if socket.assigns.selected_reserve_piece == piece_atom do
      {:noreply,
       assign(socket, selected_reserve_piece: nil, selected_square: nil, highlighted_squares: [])}
    else
      {:noreply,
       assign(socket,
         selected_reserve_piece: piece_atom,
         selected_square: nil,
         highlighted_squares: []
       )}
    end
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply,
     assign(socket,
       selected_square: nil,
       selected_reserve_piece: nil,
       highlighted_squares: []
     )}
  end

  @impl true
  def handle_info({:game_state_update, new_state}, socket) do
    {:noreply, assign(socket, game_state: new_state)}
  end

  @impl true
  def handle_info({:game_over, final_state}, socket) do
    {:noreply, assign(socket, game_state: final_state)}
  end

  # Private helper functions

  defp handle_move_attempt(socket, from, to) do
    # Deselect if clicking the same square
    if from == to do
      {:noreply, assign(socket, selected_square: nil, highlighted_squares: [])}
    else
      player_id = socket.assigns.current_player.id
      move_notation = from <> to

      case Games.make_game_move(socket.assigns.game.id, player_id, move_notation) do
        :ok ->
          {:noreply,
           assign(socket,
             selected_square: nil,
             selected_reserve_piece: nil,
             highlighted_squares: []
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Invalid move: #{inspect(reason)}")
           |> assign(selected_square: nil, highlighted_squares: [])}
      end
    end
  end

  defp handle_drop_attempt(socket, piece_atom, square) do
    player_id = socket.assigns.current_player.id

    case Games.drop_game_piece(socket.assigns.game.id, player_id, piece_atom, square) do
      :ok ->
        {:noreply,
         assign(socket,
           selected_reserve_piece: nil,
           selected_square: nil,
           highlighted_squares: []
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid drop: #{inspect(reason)}")
         |> assign(selected_reserve_piece: nil, highlighted_squares: [])}
    end
  end

  defp find_my_position(game, player_id) do
    cond do
      game.board_1_white_id == player_id -> :board_1_white
      game.board_1_black_id == player_id -> :board_1_black
      game.board_2_white_id == player_id -> :board_2_white
      game.board_2_black_id == player_id -> :board_2_black
      true -> nil
    end
  end

  defp get_my_team(:board_1_white), do: :team_1
  defp get_my_team(:board_2_black), do: :team_1
  defp get_my_team(:board_1_black), do: :team_2
  defp get_my_team(:board_2_white), do: :team_2
  defp get_my_team(nil), do: nil

  defp get_position_board(:board_1_white), do: 1
  defp get_position_board(:board_1_black), do: 1
  defp get_position_board(:board_2_white), do: 2
  defp get_position_board(:board_2_black), do: 2
  defp get_position_board(nil), do: nil

  defp get_position_color(:board_1_white), do: :white
  defp get_position_color(:board_1_black), do: :black
  defp get_position_color(:board_2_white), do: :white
  defp get_position_color(:board_2_black), do: :black
  defp get_position_color(nil), do: nil

  # Board 1 is always shown normally (white at bottom)
  # Board 2 is always flipped (black at bottom)
  # This matches the physical table layout where players sit in their chosen positions
  defp should_flip_board?(1, _position), do: false
  defp should_flip_board?(2, _position), do: true
  defp should_flip_board?(_, _), do: false

  defp get_player_name(players, player_id) do
    Map.get(players, player_id, "Waiting...")
  end

  defp format_result_message(:team_1, reason), do: "Team 1 wins! #{reason}"
  defp format_result_message(:team_2, reason), do: "Team 2 wins! #{reason}"
  defp format_result_message(:draw, reason), do: "Game drawn. #{reason}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-7xl">
      <!-- Debug Panel (Client-Side Logging) -->
      <script>
        window.addEventListener('phx:page-loading-stop', () => {
          console.log("[Bughouse] GameLive mounted", {
            playerId: "<%= @current_player.id %>",
            playerName: "<%= @current_player.display_name %>",
            myPosition: "<%= inspect(@my_position) %>",
            myTeam: "<%= inspect(@my_team) %>",
            gameId: "<%= @game.id %>",
            inviteCode: "<%= @invite_code %>"
          });
        });
      </script>
      <!-- Debug Panel (Development Only) -->
      <%= if Application.get_env(:bughouse, :env) == :dev do %>
        <div class="alert alert-info mb-4 text-xs font-mono">
          <div>
            <strong>Debug:</strong>
            Player ID: {@current_player.id} |
            Name: {@current_player.display_name} |
            Position: {inspect(@my_position)} |
            Team: {inspect(@my_team)}
          </div>
        </div>
      <% end %>
      <!-- Team 2 Header (Top) -->
      <div class="grid grid-cols-2 gap-8 mb-2">
        <.player_header
          position={:board_1_black}
          player_name={get_player_name(@players, @game.board_1_black_id)}
          my_position={@my_position}
          is_active={:board_1_black in @game_state.active_clocks}
        />
        <.player_header
          position={:board_2_white}
          player_name={get_player_name(@players, @game.board_2_white_id)}
          my_position={@my_position}
          is_active={:board_2_white in @game_state.active_clocks}
        />
      </div>

      <!-- Team 2 Clocks and Reserves (Above boards) -->
      <div class="grid grid-cols-2 gap-8 mb-4">
        <.clock_and_reserves
          position={:board_1_black}
          time_ms={@game_state.clocks.board_1_black}
          active={:board_1_black in @game_state.active_clocks}
          reserves={@game_state.reserves.board_1_black}
          can_select={@my_position == :board_1_black}
          selected_piece={@selected_reserve_piece}
        />
        <.clock_and_reserves
          position={:board_2_white}
          time_ms={@game_state.clocks.board_2_white}
          active={:board_2_white in @game_state.active_clocks}
          reserves={@game_state.reserves.board_2_white}
          can_select={@my_position == :board_2_white}
          selected_piece={@selected_reserve_piece}
        />
      </div>

      <!-- Two Boards -->
      <div class="grid grid-cols-2 gap-8 mb-4">
        <.interactive_chess_board
          board_num={1}
          fen={@game_state.board_1_fen}
          flip={should_flip_board?(1, @my_position)}
          my_position={@my_position}
          selected_square={@selected_square}
          selected_reserve_piece={@selected_reserve_piece}
          highlighted_squares={@highlighted_squares}
        />
        <.interactive_chess_board
          board_num={2}
          fen={@game_state.board_2_fen}
          flip={should_flip_board?(2, @my_position)}
          my_position={@my_position}
          selected_square={@selected_square}
          selected_reserve_piece={@selected_reserve_piece}
          highlighted_squares={@highlighted_squares}
        />
      </div>

      <!-- Team 1 Clocks and Reserves (Below boards) -->
      <div class="grid grid-cols-2 gap-8 mb-4">
        <.clock_and_reserves
          position={:board_1_white}
          time_ms={@game_state.clocks.board_1_white}
          active={:board_1_white in @game_state.active_clocks}
          reserves={@game_state.reserves.board_1_white}
          can_select={@my_position == :board_1_white}
          selected_piece={@selected_reserve_piece}
        />
        <.clock_and_reserves
          position={:board_2_black}
          time_ms={@game_state.clocks.board_2_black}
          active={:board_2_black in @game_state.active_clocks}
          reserves={@game_state.reserves.board_2_black}
          can_select={@my_position == :board_2_black}
          selected_piece={@selected_reserve_piece}
        />
      </div>

      <!-- Team 1 Header (Bottom) -->
      <div class="grid grid-cols-2 gap-8 mb-4">
        <.player_header
          position={:board_1_white}
          player_name={get_player_name(@players, @game.board_1_white_id)}
          my_position={@my_position}
          is_active={:board_1_white in @game_state.active_clocks}
        />
        <.player_header
          position={:board_2_black}
          player_name={get_player_name(@players, @game.board_2_black_id)}
          my_position={@my_position}
          is_active={:board_2_black in @game_state.active_clocks}
        />
      </div>

      <!-- Deselect button (only visible when something is selected) -->
      <%= if @selected_square || @selected_reserve_piece do %>
        <div class="fixed bottom-8 right-8 z-10">
          <button
            type="button"
            class="btn btn-primary btn-lg shadow-lg"
            phx-click="deselect_all"
          >
            ✕ Cancel Selection
          </button>
        </div>
      <% end %>

      <!-- Game Over Modal -->
      <%= if @game_state.result do %>
        <.game_result_modal
          result={@game_state.result}
          result_reason={@game_state.result_reason}
          my_team={@my_team}
        />
      <% end %>
    </div>
    """
  end
end
