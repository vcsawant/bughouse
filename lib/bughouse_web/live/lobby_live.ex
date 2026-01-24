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

  defp position_label(:board_1_white), do: "Board A - White"
  defp position_label(:board_1_black), do: "Board A - Black"
  defp position_label(:board_2_white), do: "Board B - White"
  defp position_label(:board_2_black), do: "Board B - Black"

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
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto px-4 py-8">
        <div class="mb-6">
          <a href={~p"/"} class="btn btn-ghost">← Back to Home</a>
        </div>

        <div class="max-w-4xl mx-auto">
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
          <!-- Player Slots Card -->
          <div class="card bg-base-200 mb-6">
            <div class="card-body">
              <h2 class="card-title">Players</h2>
              <!-- Quick Join Button -->
              <button
                :if={@my_position == nil and @game.status == :waiting}
                class="btn btn-success btn-lg mb-4"
                phx-click="quick_join"
              >
                Quick Join
              </button>
              <!-- 4 Player Slots -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <.player_slot
                  position={:board_1_white}
                  label={position_label(:board_1_white)}
                  game={@game}
                  players={@players}
                  my_position={@my_position}
                />
                <.player_slot
                  position={:board_1_black}
                  label={position_label(:board_1_black)}
                  game={@game}
                  players={@players}
                  my_position={@my_position}
                />
                <.player_slot
                  position={:board_2_white}
                  label={position_label(:board_2_white)}
                  game={@game}
                  players={@players}
                  my_position={@my_position}
                />
                <.player_slot
                  position={:board_2_black}
                  label={position_label(:board_2_black)}
                  game={@game}
                  players={@players}
                  my_position={@my_position}
                />
              </div>
              <!-- Leave / Start Buttons -->
              <div class="card-actions justify-end mt-6">
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
    </div>
    """
  end

  # Player Slot Component
  defp player_slot(assigns) do
    ~H"""
    <div class="bg-base-300 p-4 rounded-lg">
      <div class="flex items-center justify-between">
        <div class="flex-1">
          <div class="font-semibold text-sm text-base-content/70">{@label}</div>
          <div class="text-lg font-bold mt-1">
            <%= if position_occupied?(@game, @position) do %>
              <span class="flex items-center gap-2">
                <%= if @position == @my_position do %>
                  <span class="badge badge-primary badge-sm">You</span>
                <% end %>
                {get_player_name(@players, Map.get(@game, :"#{@position}_id"))}
              </span>
            <% else %>
              <span class="text-base-content/50">Open</span>
            <% end %>
          </div>
        </div>

        <%= if !position_occupied?(@game, @position) and @my_position == nil and @game.status == :waiting do %>
          <button
            class="btn btn-sm btn-primary"
            phx-click="join_position"
            phx-value-position={@position}
          >
            Join
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
