defmodule BughouseWeb.LobbyLive do
  use BughouseWeb, :live_view
  alias Bughouse.Games
  alias Bughouse.Accounts

  @impl true
  def mount(%{"invite_code" => code}, _session, socket) do
    require Logger
    # current_player assigned by on_mount hook
    current_player = socket.assigns.current_player

    Logger.info(
      "LobbyLive mount: player=#{current_player.id} (#{current_player.display_name}), code=#{code}"
    )

    case Games.get_game_by_invite_code(code) do
      nil ->
        Logger.warning("LobbyLive: Game not found for code=#{code}, player=#{current_player.id}")
        {:ok, socket |> put_flash(:error, "Game not found") |> redirect(to: ~p"/")}

      _game ->
        # Subscribe to real-time updates (only for connected WebSocket)
        if connected?(socket) do
          Games.subscribe_to_game(code)
          Logger.debug("LobbyLive: Subscribed to game:#{code}")
        end

        # Load game state with player names
        {game, players} = Games.get_game_with_players(code)
        my_position = find_my_position(game, current_player.id)

        Logger.info("LobbyLive: Loaded game #{game.id}, my_position=#{inspect(my_position)}")

        available_bots = Accounts.list_available_bots()

        {:ok,
         socket
         |> assign(:invite_code, code)
         |> assign(:game, game)
         |> assign(:players, players)
         |> assign(:my_position, my_position)
         |> assign(:share_url, url(socket, ~p"/lobby/#{code}"))
         |> assign(:available_bots, available_bots)
         |> assign(:bot_player_ids, MapSet.new(available_bots, fn b -> b.player.id end))}
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

  def handle_event(
        "add_bot",
        %{"bot_player_id" => bot_id, "position" => pos_str, "mode" => mode},
        socket
      ) do
    game_id = socket.assigns.game.id

    result =
      case mode do
        "dual" ->
          team = position_to_team(String.to_existing_atom(pos_str))
          Games.join_game_as_dual_bot(game_id, bot_id, team)

        _ ->
          position = String.to_existing_atom(pos_str)
          Games.join_game(game_id, bot_id, position)
      end

    case result do
      {:ok, _} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed to add bot: #{reason}")}
    end
  end

  def handle_event("remove_player", %{"player_id" => player_id}, socket) do
    case Games.leave_game_all_positions(socket.assigns.game.id, player_id) do
      {:ok, _} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed to remove player: #{reason}")}
    end
  end

  def handle_event("start_game", _params, socket) do
    case Games.start_game(socket.assigns.game.id) do
      {:ok, _game, _pid} ->
        {:noreply, socket}

      {:error, :not_enough_players} ->
        {:noreply, put_flash(socket, :error, "Need 4 players to start")}

      {:error, :bot_limit_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot start game: bot engine limit reached. Remove bots or try again later."
         )}

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

  defp teammate_position(:board_1_white), do: :board_2_black
  defp teammate_position(:board_2_black), do: :board_1_white
  defp teammate_position(:board_1_black), do: :board_2_white
  defp teammate_position(:board_2_white), do: :board_1_black

  defp position_to_team(:board_1_white), do: :team_1
  defp position_to_team(:board_2_black), do: :team_1
  defp position_to_team(:board_1_black), do: :team_2
  defp position_to_team(:board_2_white), do: :team_2

  defp bot_player?(bot_player_ids, player_id) do
    player_id && MapSet.member?(bot_player_ids, player_id)
  end

  defp is_dual_bot?(game, position, player_id) do
    tm = teammate_position(position)
    Map.get(game, :"#{tm}_id") == player_id
  end

  # Produces [{bot, mode}, ...] for the dropdown of a given open seat.
  # Excludes bots already in a game position; offers "dual" when the teammate
  # seat is also open and the bot's supported_modes allows it.
  defp filter_bots_for_position(game, position, available_bots) do
    in_game_ids =
      [:board_1_white_id, :board_1_black_id, :board_2_white_id, :board_2_black_id]
      |> Enum.map(fn field -> Map.get(game, field) end)
      |> Enum.filter(&(&1 != nil))
      |> MapSet.new()

    teammate_open = !position_occupied?(game, teammate_position(position))

    available_bots
    |> Enum.reject(fn b -> MapSet.member?(in_game_ids, b.player.id) end)
    |> Enum.flat_map(fn bot ->
      single =
        if bot.supported_modes in ["single", "both"],
          do: [{bot, "single"}],
          else: []

      dual =
        if teammate_open && bot.supported_modes in ["dual", "both"],
          do: [{bot, "dual"}],
          else: []

      single ++ dual
    end)
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
                  available_bots={@available_bots}
                  bot_player_ids={@bot_player_ids}
                />
                <.player_seat
                  position={:board_2_white}
                  color="White"
                  board="B"
                  game={@game}
                  players={@players}
                  my_position={@my_position}
                  available_bots={@available_bots}
                  bot_player_ids={@bot_player_ids}
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
                  available_bots={@available_bots}
                  bot_player_ids={@bot_player_ids}
                />
                <.player_seat
                  position={:board_2_black}
                  color="Black"
                  board="B"
                  game={@game}
                  players={@players}
                  my_position={@my_position}
                  available_bots={@available_bots}
                  bot_player_ids={@bot_player_ids}
                />
              </div>
              <div class="text-xs font-semibold text-center mt-2 opacity-50">Team 1</div>
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
        <div class="text-xs font-semibold opacity-60 mb-1">
          {@color} · Board {@board}
        </div>

        <% player_id = Map.get(@game, :"#{@position}_id") %>
        <% is_occupied = position_occupied?(@game, @position) %>
        <% is_bot = is_occupied && bot_player?(@bot_player_ids, player_id) %>

        <div class="flex items-center justify-between gap-2">
          <!-- left: name or "Open Seat" -->
          <div class="flex-1 min-w-0">
            <%= if is_occupied do %>
              <div class="flex items-center gap-2">
                <%= if is_bot do %>
                  <span class="badge badge-accent badge-sm">🤖</span>
                <% end %>
                <%= if @position == @my_position do %>
                  <span class="badge badge-primary badge-sm">You</span>
                <% end %>
                <span class="font-bold truncate">
                  {get_player_name(@players, player_id)}
                </span>
                <%= if is_bot && is_dual_bot?(@game, @position, player_id) do %>
                  <span class="badge badge-sm badge-outline">Dual</span>
                <% end %>
              </div>
            <% else %>
              <span class="text-base-content/50 text-sm">Open Seat</span>
            <% end %>
          </div>
          
    <!-- right: action buttons -->
          <%= if is_occupied && @game.status == :waiting && @position != @my_position do %>
            <button
              class="btn btn-xs btn-ghost btn-error"
              phx-click="remove_player"
              phx-value-player_id={player_id}
            >
              ✕
            </button>
          <% end %>

          <%= if !is_occupied && @game.status == :waiting do %>
            <div class="flex gap-1">
              <%= if @my_position == nil do %>
                <button
                  class="btn btn-sm btn-primary"
                  phx-click="join_position"
                  phx-value-position={@position}
                >
                  Sit Here
                </button>
              <% end %>

              <% filtered_bots = filter_bots_for_position(@game, @position, @available_bots) %>
              <div class="dropdown dropdown-top">
                <label tabindex="0" class="btn btn-sm btn-outline">
                  Add Bot ▾
                </label>
                <ul
                  tabindex="0"
                  class="dropdown-content menu bg-base-200 rounded-lg p-2 w-56 shadow z-10"
                >
                  <%= if Enum.empty?(filtered_bots) do %>
                    <li>
                      <span class="px-2 py-1 text-sm opacity-50">No bots available</span>
                    </li>
                  <% else %>
                    <%= for {bot, mode} <- filtered_bots do %>
                      <li>
                        <button
                          class="w-full text-left px-2 py-1 text-sm hover:bg-base-300 rounded"
                          phx-click="add_bot"
                          phx-value-bot_player_id={bot.player.id}
                          phx-value-position={@position}
                          phx-value-mode={mode}
                        >
                          <%= if mode == "dual" do %>
                            Fill Team: {bot.player.display_name}
                          <% else %>
                            {bot.player.display_name}
                          <% end %>
                        </button>
                      </li>
                    <% end %>
                  <% end %>
                </ul>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
