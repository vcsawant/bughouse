defmodule BughouseWeb.ChessComponents do
  @moduledoc """
  Provides chess-specific UI components.

  This module contains components for rendering chess boards, pieces,
  and related chess game UI elements. These components are specific to
  the Bughouse chess application.

  ## Components

    * `chess_board/1` - Renders a chess board from FEN notation
    * `chess_board_theme_selector/1` - UI for selecting board color themes
    * `captured_pieces/1` - Display captured pieces (for future use)

  ## Usage

  These components are automatically imported in your views via the
  `use BughouseWeb, :html` macro, so you can use them directly:

      <.chess_board fen="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR" />

  ## Chess Board Theming

  Chess boards use an independent theming system from the app's light/dark
  mode. Users can choose board colors separately via the theme selector.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: BughouseWeb.Endpoint,
    router: BughouseWeb.Router,
    statics: BughouseWeb.static_paths()

  alias Phoenix.LiveView.JS

  @doc """
  Renders a chess board with pieces from a FEN string.

  FEN (Forsyth-Edwards Notation) is the standard notation for describing
  chess positions. This component renders an 8x8 chess board with Unicode
  pieces based on the FEN string.

  ## Examples

      # Starting position
      <.chess_board fen="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR" />

      # Custom size
      <.chess_board fen="..." size="lg" />

      # Flipped board (black at bottom)
      <.chess_board fen="..." flip={true} />

  ## Attributes

    * `fen` - FEN string for the position (only the piece placement part)
    * `size` - Board size: "sm", "md", "lg", "xl" (default: "md")
    * `flip` - Flip board to show black at bottom (default: false)
    * `theme` - Board theme: "classic", "green", "blue", "gray", "purple" (default: "classic")
    * `show_coordinates` - Show rank/file labels (default: false)
    * `class` - Additional CSS classes

  ## FEN Format

  FEN uses these characters for pieces:
  - Uppercase = White pieces: K=King, Q=Queen, R=Rook, B=Bishop, N=Knight, P=Pawn
  - Lowercase = Black pieces: k, q, r, b, n, p
  - Numbers = Empty squares (1-8)
  - "/" = New rank (row)

  Example: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR" (starting position)
  """
  attr :fen, :string,
    default: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
    doc: "FEN string for board position"

  attr :size, :string, default: "md", values: ~w(sm md lg xl)
  attr :flip, :boolean, default: false, doc: "Flip board (black at bottom)"
  attr :theme, :string, default: "classic", values: ~w(classic green blue gray purple)
  attr :show_coordinates, :boolean, default: false
  attr :class, :any, default: nil

  def chess_board(assigns) do
    # Parse FEN string into board representation
    board = parse_fen(assigns.fen)

    # Determine board size in pixels
    size_class =
      case assigns.size do
        "sm" -> "w-48 h-48"
        "md" -> "w-64 h-64"
        "lg" -> "w-80 h-80"
        "xl" -> "w-96 h-96"
      end

    # Prepare board data for rendering
    # If flipped, reverse both ranks and files to show from black's perspective
    display_board =
      if assigns.flip do
        board
        |> Enum.reverse()
        |> Enum.map(&Enum.reverse/1)
      else
        board
      end

    assigns =
      assigns
      |> assign(:board, display_board)
      |> assign(:size_class, size_class)
      |> assign(:theme_attr, if(assigns.theme == "classic", do: nil, else: assigns.theme))

    ~H"""
    <div
      class={["inline-block", @class]}
      data-chess-theme={@theme_attr}
      data-chess-board="true"
    >
      <div class={[
        "grid grid-cols-8 gap-0 shadow-lg",
        "border-[0.25rem] rounded-sm",
        @size_class,
        "border-[var(--chess-board-border,oklch(40%_0.06_62))]"
      ]}>
        <%= for {rank, rank_idx} <- Enum.with_index(@board) do %>
          <%= for {piece, file_idx} <- Enum.with_index(rank) do %>
            <% # Calculate if square should be light or dark
            # "Light on right" - bottom-right square is always light for both players
            # Even sum of indices = light square
            is_light = rem(rank_idx + file_idx, 2) == 0

            square_color =
              if is_light,
                do: "bg-[var(--chess-light-square,oklch(85%_0.05_72))]",
                else: "bg-[var(--chess-dark-square,oklch(55%_0.06_62))]"

            # Determine piece color class
            piece_color_class =
              if piece do
                if String.upcase(piece) == piece,
                  do: "chess-piece-white",
                  else: "chess-piece-black"
              end %>
            <div class={[
              "aspect-square flex items-center justify-center relative overflow-hidden",
              "select-none cursor-pointer",
              "transition-colors duration-150",
              "hover:brightness-95",
              square_color
            ]}>
              <%= if piece do %>
                <span class={[
                  "chess-piece",
                  piece_color_class,
                  "text-[2.5rem] leading-none"
                ]}>
                  {piece_to_unicode(piece)}
                </span>
              <% end %>

              <%= if @show_coordinates do %>
                <%= if file_idx == 0 do %>
                  <% # Rank number: 8 at top, 1 at bottom (when not flipped)
                  # After flipping, 1 at top, 8 at bottom
                  rank_number = if @flip, do: rank_idx + 1, else: 8 - rank_idx %>
                  <span class="absolute bottom-0.5 left-0.5 text-[0.6rem] opacity-60 font-semibold pointer-events-none">
                    {rank_number}
                  </span>
                <% end %>
                <%= if rank_idx == 7 do %>
                  <% # File letter: a-h from left to right (when not flipped)
                  # After flipping, h-a from left to right
                  file_letter = if @flip, do: ?h - file_idx, else: ?a + file_idx %>
                  <span class="absolute top-0.5 right-0.5 text-[0.6rem] opacity-60 font-semibold pointer-events-none">
                    {<<file_letter>>}
                  </span>
                <% end %>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a chess clock/timer with tenth-second precision.

  Displays time in MM:SS.T format (minutes:seconds.tenths) with visual
  indicators for active/inactive state. Time management is server-side -
  this component only displays the current value.

  ## Examples

      # Basic timer
      <.chess_clock time_ms={900000} active={true} />

      # With player color
      <.chess_clock
        time_ms={@player_time}
        active={@is_current_turn}
        color={:white}
      />

  ## Attributes

    * `time_ms` - Time remaining in milliseconds
    * `active` - Whether this clock is currently running
    * `color` - Player color (:white or :black), optional
    * `class` - Additional CSS classes

  ## Server-Side Time Management

  This component is presentation-only. The actual time countdown happens
  server-side in your LiveView using `:timer.send_interval/2`.

  **Important:** To show tenths of a second, tick every 100ms (not 1000ms):

      def mount(_params, _session, socket) do
        if connected?(socket) do
          # Start precise interval timer (no drift!)
          {:ok, timer_ref} = :timer.send_interval(100, :timer_tick)
          socket = assign(socket, timer_ref: timer_ref)
        else
          socket = socket
        end

        {:ok, assign(socket, time_ms: 900_000, active: true)}
      end

      def handle_info(:timer_tick, socket) do
        if socket.assigns.active do
          # Decrement by 100ms for tenth-second precision
          new_time = max(0, socket.assigns.time_ms - 100)
          {:noreply, assign(socket, time_ms: new_time)}
        else
          # Timer still fires, just don't decrement when inactive
          {:noreply, socket}
        end
      end

      # Clean up timer on process termination
      def terminate(_reason, socket) do
        if socket.assigns[:timer_ref] do
          :timer.cancel(socket.assigns.timer_ref)
        end
        :ok
      end
  """
  attr :id, :string, default: nil, doc: "Unique ID for the clock element"
  attr :time_ms, :integer, required: true, doc: "Time remaining in milliseconds"
  attr :active, :boolean, default: false, doc: "Whether the clock is running"
  attr :color, :atom, default: nil, values: [nil, :white, :black]
  attr :last_update_at, :integer, default: nil, doc: "Unix timestamp (ms) of last server update"
  attr :class, :any, default: nil

  def chess_clock(assigns) do
    # Convert milliseconds to minutes and seconds for initial display (MM:SS format)
    total_seconds = div(assigns.time_ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    # Determine urgency level for styling
    urgency =
      cond do
        assigns.time_ms <= 10_000 -> :critical
        assigns.time_ms <= 30_000 -> :low
        true -> :normal
      end

    assigns =
      assigns
      |> assign(:minutes, minutes)
      |> assign(:seconds, seconds)
      |> assign(:urgency, urgency)

    ~H"""
    <div
      class={[
        "chess-clock relative",
        "font-mono text-3xl font-bold",
        "px-6 py-3 rounded-lg",
        "transition-all duration-300",
        "border-2",
        @active && "ring-4 ring-primary ring-opacity-50",
        @active && @urgency == :critical && "animate-pulse",
        @urgency == :critical && "bg-error text-error-content border-error",
        @urgency == :low && "bg-warning text-warning-content border-warning",
        @urgency == :normal && @active && "bg-primary text-primary-content border-primary",
        @urgency == :normal && !@active && "bg-base-200 text-base-content border-base-300 opacity-60",
        @class
      ]}
      data-time-ms={@time_ms}
      data-active={@active}
      phx-hook="ChessClockCountdown"
      id={@id || "chess-clock-#{:erlang.phash2(@color || :default)}"}
    >
      <div class="flex items-center justify-center gap-1">
        <%= if @active do %>
          <span class="absolute -top-1 -right-1 flex h-3 w-3" data-active-indicator>
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75">
            </span>
            <span class="relative inline-flex rounded-full h-3 w-3 bg-primary"></span>
          </span>
        <% end %>

        <!-- DaisyUI Countdown Component (MM:SS format) -->
        <div class="grid grid-flow-col gap-1 text-center auto-cols-max">
          <!-- Minutes -->
          <div class="flex flex-col">
            <span class="countdown tabular-nums text-3xl" data-minutes>
              <span style={"--value:#{@minutes};"}></span>
            </span>
          </div>
          <span class={[@active && "animate-pulse"]}>:</span>
          <!-- Seconds -->
          <div class="flex flex-col">
            <span class="countdown tabular-nums text-3xl" data-seconds>
              <span style={"--value:#{@seconds};"}></span>
            </span>
          </div>
        </div>
      </div>

      <%= if @color do %>
        <div class="absolute -bottom-2 left-1/2 transform -translate-x-1/2">
          <span class={[
            "text-xs px-2 py-0.5 rounded-full font-sans font-semibold",
            @color == :white && "bg-white text-black",
            @color == :black && "bg-black text-white"
          ]}>
            {if @color == :white, do: "White", else: "Black"}
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a chess board theme selector.

  Allows users to switch between different chess board color schemes.
  The selected theme is saved to localStorage and persists across sessions.

  ## Examples

      <.chess_board_theme_selector />

  ## Available Themes

    * `classic` - Traditional brown/cream (like chess.com)
    * `green` - Tournament green/white
    * `blue` - Ocean blue/white
    * `gray` - Modern monochrome
    * `purple` - Royal purple/lavender
  """
  def chess_board_theme_selector(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2 items-center">
      <span class="text-sm font-medium">Board Theme:</span>

      <button
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click={JS.dispatch("phx:set-chess-theme")}
        data-phx-chess-theme="classic"
        title="Classic Brown"
      >
        <div class="w-6 h-6 rounded border-2 border-base-300 grid grid-cols-2 grid-rows-2">
          <div class="bg-[oklch(85%_0.05_72)]"></div>
          <div class="bg-[oklch(55%_0.06_62)]"></div>
          <div class="bg-[oklch(55%_0.06_62)]"></div>
          <div class="bg-[oklch(85%_0.05_72)]"></div>
        </div>
      </button>

      <button
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click={JS.dispatch("phx:set-chess-theme")}
        data-phx-chess-theme="green"
        title="Tournament Green"
      >
        <div class="w-6 h-6 rounded border-2 border-base-300 grid grid-cols-2 grid-rows-2">
          <div class="bg-[oklch(95%_0.02_120)]"></div>
          <div class="bg-[oklch(60%_0.15_145)]"></div>
          <div class="bg-[oklch(60%_0.15_145)]"></div>
          <div class="bg-[oklch(95%_0.02_120)]"></div>
        </div>
      </button>

      <button
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click={JS.dispatch("phx:set-chess-theme")}
        data-phx-chess-theme="blue"
        title="Ocean Blue"
      >
        <div class="w-6 h-6 rounded border-2 border-base-300 grid grid-cols-2 grid-rows-2">
          <div class="bg-[oklch(93%_0.02_240)]"></div>
          <div class="bg-[oklch(50%_0.15_240)]"></div>
          <div class="bg-[oklch(50%_0.15_240)]"></div>
          <div class="bg-[oklch(93%_0.02_240)]"></div>
        </div>
      </button>

      <button
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click={JS.dispatch("phx:set-chess-theme")}
        data-phx-chess-theme="gray"
        title="Modern Gray"
      >
        <div class="w-6 h-6 rounded border-2 border-base-300 grid grid-cols-2 grid-rows-2">
          <div class="bg-[oklch(90%_0_0)]"></div>
          <div class="bg-[oklch(50%_0_0)]"></div>
          <div class="bg-[oklch(50%_0_0)]"></div>
          <div class="bg-[oklch(90%_0_0)]"></div>
        </div>
      </button>

      <button
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click={JS.dispatch("phx:set-chess-theme")}
        data-phx-chess-theme="purple"
        title="Royal Purple"
      >
        <div class="w-6 h-6 rounded border-2 border-base-300 grid grid-cols-2 grid-rows-2">
          <div class="bg-[oklch(92%_0.03_300)]"></div>
          <div class="bg-[oklch(45%_0.15_300)]"></div>
          <div class="bg-[oklch(45%_0.15_300)]"></div>
          <div class="bg-[oklch(92%_0.03_300)]"></div>
        </div>
      </button>
    </div>
    """
  end

  @doc """
  Combined clock and reserve pieces display.

  Displays a chess clock on the left and reserve pieces on the right in a flex container.
  This is used in the game view to show each player's time and available pieces for dropping.

  ## Attributes

    * `position` - Player position (:board_1_white, :board_1_black, etc.)
    * `time_ms` - Time remaining in milliseconds
    * `active` - Whether this clock is currently running
    * `reserves` - Map of reserve pieces %{p: 2, n: 1, b: 0, r: 1, q: 0}
    * `can_select` - Whether the current user can select reserve pieces
    * `selected_piece` - Currently selected reserve piece atom (:p, :n, etc.)
  """
  attr :position, :atom, required: true
  attr :time_ms, :integer, required: true
  attr :active, :boolean, default: false
  attr :reserves, :map, required: true
  attr :can_select, :boolean, default: false
  attr :selected_piece, :atom, default: nil

  def clock_and_reserves(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4">
      <!-- Clock (left-aligned) -->
      <div class="flex-shrink-0">
        <.chess_clock
          id={"clock-#{@position}"}
          time_ms={@time_ms}
          active={@active}
          color={get_position_color(@position)}
        />
      </div>

      <!-- Reserve Pieces (right-aligned) -->
      <div class="flex-1 flex justify-end">
        <.reserve_pieces
          pieces={@reserves}
          can_select={@can_select}
          selected_piece={@selected_piece}
        />
      </div>
    </div>
    """
  end

  @doc """
  Display reserve pieces in standard order: pawn, knight, bishop, rook, queen.

  Reserve pieces are captured pieces that can be dropped back onto the board.
  This component shows the count of each piece type and allows selection when enabled.

  ## Attributes

    * `pieces` - Map of piece counts %{p: 2, n: 1, b: 0, r: 1, q: 0}
    * `can_select` - Whether the user can click to select pieces
    * `selected_piece` - Currently selected piece atom
  """
  attr :pieces, :map, required: true
  attr :can_select, :boolean, default: false
  attr :selected_piece, :atom, default: nil

  def reserve_pieces(assigns) do
    ~H"""
    <div class="flex gap-2 items-center">
      <%= for piece_type <- [:p, :n, :b, :r, :q] do %>
        <% count = Map.get(@pieces, piece_type, 0) %>
        <button
          type="button"
          class={[
            "btn btn-sm relative",
            count == 0 && "opacity-30 cursor-not-allowed",
            @selected_piece == piece_type && "btn-primary ring-2 ring-primary"
          ]}
          disabled={count == 0 or not @can_select}
          phx-click="select_reserve_piece"
          phx-value-piece={Atom.to_string(piece_type)}
        >
          <span class="text-2xl">{piece_type_to_unicode(piece_type)}</span>
          <%= if count > 1 do %>
            <span class="absolute bottom-0 right-0 text-xs font-bold bg-base-100 px-1 rounded">
              {count}
            </span>
          <% end %>
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Interactive chess board with click handlers for moves and drops.

  This board component handles user interaction for selecting pieces,
  making moves, and dropping reserve pieces.

  ## Attributes

    * `board_num` - Board number (1 or 2)
    * `fen` - FEN string for current position
    * `flip` - Whether to flip the board
    * `my_position` - Current player's position (nil for spectator)
    * `selected_square` - Currently selected square notation
    * `selected_reserve_piece` - Currently selected reserve piece
    * `highlighted_squares` - List of valid destination squares
  """
  attr :board_num, :integer, required: true
  attr :fen, :string, required: true
  attr :flip, :boolean, default: false
  attr :my_position, :atom, default: nil
  attr :selected_square, :string, default: nil
  attr :selected_reserve_piece, :atom, default: nil
  attr :highlighted_squares, :list, default: []

  def interactive_chess_board(assigns) do
    # Parse FEN and render board with click handlers
    board = parse_fen(assigns.fen)

    # Determine board size
    size_class = "w-96 h-96"

    # Check if this is the current player's board
    is_my_board = is_players_board?(assigns.my_position, assigns.board_num)

    # Prepare board data for rendering
    display_board =
      if assigns.flip do
        board
        |> Enum.reverse()
        |> Enum.map(&Enum.reverse/1)
      else
        board
      end

    assigns =
      assigns
      |> assign(:board, display_board)
      |> assign(:size_class, size_class)
      |> assign(:is_my_board, is_my_board)

    ~H"""
    <div class="relative inline-block">
      <div class={[
        "grid grid-cols-8 gap-0 shadow-lg",
        "border-[0.25rem] rounded-sm",
        @size_class,
        "border-[var(--chess-board-border,oklch(40%_0.06_62))]"
      ]}>
        <%= for {rank, rank_idx} <- Enum.with_index(@board) do %>
          <%= for {piece, file_idx} <- Enum.with_index(rank) do %>
            <% # Calculate square notation
            square_notation = square_to_notation(file_idx, rank_idx, @flip)

            # Calculate if square should be light or dark
            is_light = rem(rank_idx + file_idx, 2) == 0

            square_color =
              if is_light,
                do: "bg-[var(--chess-light-square,oklch(85%_0.05_72))]",
                else: "bg-[var(--chess-dark-square,oklch(55%_0.06_62))]"

            # Determine piece color class
            piece_color_class =
              if piece do
                if String.upcase(piece) == piece,
                  do: "chess-piece-white",
                  else: "chess-piece-black"
              end

            # Check if this square is selected or highlighted
            # Only show selection/highlights on player's own board
            is_selected = @selected_square == square_notation && @is_my_board
            is_highlighted = square_notation in @highlighted_squares && @is_my_board
            # Only show drop targets on player's own board
            has_drop_target = @selected_reserve_piece != nil && @is_my_board %>
            <div
              class={[
                "aspect-square flex items-center justify-center relative overflow-hidden",
                "select-none cursor-pointer",
                "transition-colors duration-150",
                "hover:brightness-95",
                square_color,
                is_selected && "ring-4 ring-inset ring-blue-500",
                is_highlighted && "bg-green-400 bg-opacity-50",
                has_drop_target && piece == nil && "bg-yellow-300 bg-opacity-30"
              ]}
              phx-click="select_square"
              phx-value-square={square_notation}
              phx-value-board={@board_num}
            >
              <%= if piece do %>
                <span class={[
                  "chess-piece",
                  piece_color_class,
                  "text-[2.5rem] leading-none"
                ]}>
                  {piece_to_unicode(piece)}
                </span>
              <% end %>

              <!-- Show rank/file coordinates -->
              <%= if file_idx == 0 do %>
                <% rank_number = if @flip, do: rank_idx + 1, else: 8 - rank_idx %>
                <span class="absolute bottom-0.5 left-0.5 text-[0.6rem] opacity-60 font-semibold pointer-events-none">
                  {rank_number}
                </span>
              <% end %>
              <%= if rank_idx == 7 do %>
                <% file_letter = if @flip, do: ?h - file_idx, else: ?a + file_idx %>
                <span class="absolute top-0.5 right-0.5 text-[0.6rem] opacity-60 font-semibold pointer-events-none">
                  {<<file_letter>>}
                </span>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Display player name and position info.

  Shows the player's name, color, and board number.
  Highlights the current user's position and shows turn indicator.

  ## Attributes

    * `position` - Player position atom
    * `player_name` - Display name of the player
    * `my_position` - Current user's position (for highlighting)
    * `is_active` - Whether it's this player's turn (optional)
  """
  attr :position, :atom, required: true
  attr :player_name, :string, required: true
  attr :my_position, :atom, default: nil
  attr :is_active, :boolean, default: false

  def player_header(assigns) do
    assigns =
      assigns
      |> assign(:color, get_position_color(assigns.position))
      |> assign(:board, get_position_board(assigns.position))
      |> assign(:is_me, assigns.position == assigns.my_position)

    ~H"""
    <div class={[
      "text-center p-3 rounded-lg transition-all",
      @is_me && "bg-primary bg-opacity-20 ring-2 ring-primary"
    ]}>
      <div class={["font-semibold text-lg flex items-center justify-center gap-2", @is_me && "text-primary"]}>
        <%= if @is_active do %>
          <span class="text-success text-2xl" title="Active turn">▶</span>
        <% end %>
        <span>
          {@player_name} <%= if @is_me, do: "(You)" %>
        </span>
      </div>
      <div class="text-sm opacity-70 capitalize">
        {@color |> Atom.to_string()} · Board {@board}
      </div>
    </div>
    """
  end

  @doc """
  Game result modal displayed when the game ends.

  Shows the winning team, result reason, and provides navigation back to home.

  ## Attributes

    * `result` - Result atom (:team_1, :team_2, or :draw)
    * `result_reason` - Human-readable reason string
    * `my_team` - Current player's team (for personalized messaging)
  """
  attr :result, :atom, required: true
  attr :result_reason, :string, required: true
  attr :my_team, :atom, default: nil

  def game_result_modal(assigns) do
    assigns = assign(assigns, :is_winner, assigns.result == assigns.my_team)

    ~H"""
    <div class="modal modal-open">
      <div class="modal-box text-center">
        <h3 class="font-bold text-3xl mb-4">
          <%= if @is_winner do %>
            🎉 Congratulations! You Won!
          <% else %>
            <%= if @result == :draw do %>
              🤝 Game Drawn
            <% else %>
              😔 Better Luck Next Time
            <% end %>
          <% end %>
        </h3>

        <p class="text-xl mb-6">
          {format_result_message(@result, @result_reason)}
        </p>

        <div class="modal-action justify-center">
          <.link navigate={~p"/"} class="btn btn-primary btn-lg">
            Back to Home
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp get_position_color(:board_1_white), do: :white
  defp get_position_color(:board_1_black), do: :black
  defp get_position_color(:board_2_white), do: :white
  defp get_position_color(:board_2_black), do: :black

  defp get_position_board(:board_1_white), do: 1
  defp get_position_board(:board_1_black), do: 1
  defp get_position_board(:board_2_white), do: 2
  defp get_position_board(:board_2_black), do: 2
  defp get_position_board(nil), do: nil

  # Check if a board number matches the player's position
  defp is_players_board?(nil, _board_num), do: false
  defp is_players_board?(position, board_num) do
    get_position_board(position) == board_num
  end

  defp format_result_message(:team_1, reason), do: "Team 1 wins! #{reason}"
  defp format_result_message(:team_2, reason), do: "Team 2 wins! #{reason}"
  defp format_result_message(:draw, reason), do: "Game drawn. #{reason}"

  # Convert square indices to chess notation (e.g., "e2")
  defp square_to_notation(file_idx, rank_idx, flip) do
    file = if flip, do: ?h - file_idx, else: ?a + file_idx
    rank = if flip, do: rank_idx + 1, else: 8 - rank_idx
    <<file, rank + ?0>>
  end

  # Convert piece type atom to Unicode symbol
  defp piece_type_to_unicode(:p), do: "♙"
  defp piece_type_to_unicode(:n), do: "♘"
  defp piece_type_to_unicode(:b), do: "♗"
  defp piece_type_to_unicode(:r), do: "♖"
  defp piece_type_to_unicode(:q), do: "♕"

  # Parse FEN string into 8x8 board representation
  # Returns: List of 8 ranks, each rank is a list of 8 squares (nil or piece char)
  # Expects simplified FEN with only piece placement (e.g., "rnbqkbnr/pppppppp/.../RNBQKBNR")
  defp parse_fen(fen) do
    fen
    |> String.split("/")
    |> Enum.map(&parse_rank/1)
  end

  # Parse a single rank (row) of FEN notation
  # Example: "rnbqkbnr" or "8" or "p2p3p"
  defp parse_rank(rank_string) do
    rank_string
    |> String.graphemes()
    |> Enum.flat_map(fn char ->
      case Integer.parse(char) do
        {num, ""} -> List.duplicate(nil, num)
        :error -> [char]
      end
    end)
  end

  # Convert FEN piece character to Unicode chess piece
  defp piece_to_unicode(piece) do
    case piece do
      # White pieces
      "K" -> "♔"
      "Q" -> "♕"
      "R" -> "♖"
      "B" -> "♗"
      "N" -> "♘"
      "P" -> "♙"
      # Black pieces
      "k" -> "♚"
      "q" -> "♛"
      "r" -> "♜"
      "b" -> "♝"
      "n" -> "♞"
      "p" -> "♟"
      _ -> ""
    end
  end
end
