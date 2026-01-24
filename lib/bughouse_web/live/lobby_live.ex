defmodule BughouseWeb.LobbyLive do
  use BughouseWeb, :live_view
  alias Bughouse.Games

  @impl true
  def mount(%{"invite_code" => code}, _session, socket) do
    # current_player assigned by on_mount hook

    case Games.get_game_by_invite_code(code) do
      nil ->
        {:ok, socket |> put_flash(:error, "Game not found") |> redirect(to: ~p"/")}

      _game ->
        # Subscribe to real-time updates (only for connected WebSocket)
        if connected?(socket), do: Games.subscribe_to_game(code)

        # Load game state with player names
        {game, players} = Games.get_game_with_players(code)

        {:ok,
         socket
         |> assign(:invite_code, code)
         |> assign(:game, game)
         |> assign(:players, players)
         |> assign(:my_position, find_my_position(game, socket.assigns.current_player.id))
         |> assign(:share_url, url(socket, ~p"/lobby/#{code}"))}
    end
  end

  # Event Handlers (user interactions)

  @impl true
  def handle_event("join_position", %{"position" => pos_str}, socket) do
    position = String.to_existing_atom(pos_str)
    player_id = socket.assigns.current_player.id

    case Games.join_game(socket.assigns.game.id, player_id, position) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, :position_taken} ->
        {:noreply, put_flash(socket, :error, "Position already taken")}

      {:error, :player_already_joined} ->
        {:noreply, put_flash(socket, :error, "You're already in this game")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to join: #{reason}")}
    end
  end

  def handle_event("quick_join", _params, socket) do
    player_id = socket.assigns.current_player.id

    case Games.join_game_random(socket.assigns.game.id, player_id) do
      {:ok, {_game, _position}} ->
        {:noreply, socket}

      {:error, :game_full} ->
        {:noreply, put_flash(socket, :error, "Game is full")}

      {:error, :player_already_joined} ->
        {:noreply, put_flash(socket, :error, "You're already in this game")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to join: #{reason}")}
    end
  end

  def handle_event("leave_game", _params, socket) do
    player_id = socket.assigns.current_player.id

    case Games.leave_game(socket.assigns.game.id, player_id) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not leave")}
    end
  end

  def handle_event("start_game", _params, socket) do
    case Games.start_game(socket.assigns.game.id) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, :not_enough_players} ->
        {:noreply, put_flash(socket, :error, "Need 4 players to start")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{reason}")}
    end
  end

  # PubSub Message Handlers (real-time updates)

  @impl true
  def handle_info({:player_joined, game}, socket) do
    {game, players} = Games.get_game_with_players(game.invite_code)

    {:noreply,
     socket
     |> assign(:game, game)
     |> assign(:players, players)
     |> assign(:my_position, find_my_position(game, socket.assigns.current_player.id))}
  end

  def handle_info({:player_left, game}, socket) do
    {game, players} = Games.get_game_with_players(game.invite_code)

    {:noreply,
     socket
     |> assign(:game, game)
     |> assign(:players, players)
     |> assign(:my_position, find_my_position(game, socket.assigns.current_player.id))}
  end

  def handle_info({:game_started, game}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Game started!")
     |> redirect(to: ~p"/game/#{game.invite_code}")}
  end

  # Helper Functions

  defp find_my_position(game, player_id) do
    cond do
      game.board_1_white_id == player_id -> :board_1_white
      game.board_1_black_id == player_id -> :board_1_black
      game.board_2_white_id == player_id -> :board_2_white
      game.board_2_black_id == player_id -> :board_2_black
      true -> nil
    end
  end

  defp position_occupied?(game, position) do
    Map.get(game, :"#{position}_id") != nil
  end

  defp get_player_name(players, player_id) do
    Map.get(players, player_id, "Unknown")
  end

  defp can_start_game?(game) do
    game.status == :waiting and
      not is_nil(game.board_1_white_id) and
      not is_nil(game.board_1_black_id) and
      not is_nil(game.board_2_white_id) and
      not is_nil(game.board_2_black_id)
  end

  # Template (render function)
  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="max-w-6xl mx-auto">
          <h1 class="text-4xl font-bold mb-8 text-center">Game Lobby</h1>
          <!-- Invite Code Card -->
          <div class="card bg-base-200 mb-6">
            <div class="card-body">
              <h2 class="card-title">Invite Your Friends</h2>
              <p class="mb-4">Share this link to invite players:</p>

              <div class="flex gap-2 items-center">
                <input
                  type="text"
                  readonly
                  value={@share_url}
                  class="input input-bordered flex-1 font-mono text-sm"
                  id="share-url-input"
                />
                <button
                  class="btn btn-primary"
                  onclick={"navigator.clipboard.writeText('#{@share_url}')"}
                >
                  Copy Link
                </button>
              </div>

              <div class="bg-base-300 p-4 rounded-lg text-center mt-4">
                <span class="text-sm text-base-content/70">Invite Code:</span>
                <code class="text-2xl font-mono font-bold block">{@invite_code}</code>
              </div>
            </div>
          </div>
          <!-- Bughouse Table Layout -->
          <div class="card bg-base-200 mb-6">
            <div class="card-body">
              <div class="flex items-center justify-between mb-4">
                <h2 class="card-title">Bughouse Table</h2>
                <button
                  :if={@my_position == nil and @game.status == :waiting}
                  class="btn btn-success"
                  phx-click="quick_join"
                >
                  Quick Join
                </button>
              </div>
              <!-- Team 2 (Top Side) -->
              <div class="mb-3">
                <div class="text-xs font-semibold text-center mb-2 opacity-50">Team 2</div>
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                  <.player_seat
                    position={:board_1_black}
                    color="Black"
                    board="A"
                    game={@game}
                    players={@players}
                    my_position={@my_position}
                  />
                  <.player_seat
                    position={:board_2_white}
                    color="White"
                    board="B"
                    game={@game}
                    players={@players}
                    my_position={@my_position}
                  />
                </div>
              </div>
              <!-- Two Boards Side by Side -->
              <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 my-6">
                <!-- Board A (White bottom) -->
                <div class="flex flex-col items-center">
                  <div class="text-sm font-semibold mb-2 opacity-70">Board A</div>
                  <.chess_board
                    fen="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
                    size="lg"
                    flip={false}
                  />
                </div>
                <!-- Board B (Black bottom) -->
                <div class="flex flex-col items-center">
                  <div class="text-sm font-semibold mb-2 opacity-70">Board B</div>
                  <.chess_board
                    fen="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
                    size="lg"
                    flip={true}
                  />
                </div>
              </div>
              <!-- Team 1 (Bottom Side) -->
              <div class="mb-4">
                <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                  <.player_seat
                    position={:board_1_white}
                    color="White"
                    board="A"
                    game={@game}
                    players={@players}
                    my_position={@my_position}
                  />
                  <.player_seat
                    position={:board_2_black}
                    color="Black"
                    board="B"
                    game={@game}
                    players={@players}
                    my_position={@my_position}
                  />
                </div>
                <div class="text-xs font-semibold text-center mt-2 opacity-50">Team 1</div>
              </div>
              <!-- Chess Board Theme Selector -->
              <div class="bg-base-300 rounded-lg p-4 mb-4">
                <.chess_board_theme_selector />
              </div>
              <!-- Team Info -->
              <div class="alert alert-info mb-4">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  class="stroke-current shrink-0 w-6 h-6"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <div class="text-sm">
                  <strong>Teams:</strong>
                  Team 1 (White/A + Black/B) vs Team 2 (Black/A + White/B) · Partners sit next to each other
                </div>
              </div>
              <!-- Action Buttons -->
              <div class="card-actions justify-end">
                <button
                  :if={@my_position != nil}
                  class="btn btn-ghost"
                  phx-click="leave_game"
                >
                  Leave Game
                </button>

                <button
                  class="btn btn-primary"
                  phx-click="start_game"
                  disabled={!can_start_game?(@game)}
                >
                  {if can_start_game?(@game), do: "Start Game", else: "Waiting for Players..."}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    """
  end

  # Player Seat Component (positioned around table)
  defp player_seat(assigns) do
    ~H"""
    <div class="w-full">
      <div class="bg-base-300 rounded-lg p-3 border-2 border-base-content/10">
        <div class="flex items-center justify-between gap-3">
          <div class="flex-1 min-w-0">
            <div class="text-xs font-semibold opacity-60 mb-1">
              {@color} · Board {@board}
            </div>
            <%= if position_occupied?(@game, @position) do %>
              <div class="flex items-center gap-2">
                <%= if @position == @my_position do %>
                  <span class="badge badge-primary badge-sm">You</span>
                <% end %>
                <span class="font-bold truncate">
                  {get_player_name(@players, Map.get(@game, :"#{@position}_id"))}
                </span>
              </div>
            <% else %>
              <span class="text-base-content/50 text-sm">Open Seat</span>
            <% end %>
          </div>
          <%= if !position_occupied?(@game, @position) and @my_position == nil and @game.status == :waiting do %>
            <button
              class="btn btn-sm btn-primary"
              phx-click="join_position"
              phx-value-position={@position}
            >
              Sit Here
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
