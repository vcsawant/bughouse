defmodule BughouseWeb.GameHistoryComponents do
  @moduledoc """
  Shared components for game history display, used by AccountLive and PlayerProfileLive.
  """
  use Phoenix.Component
  import BughouseWeb.CoreComponents

  @doc """
  Renders the full game history view: player stats, rating graph, games table, and pagination.

  Emits `filter_rating` and `change_page` events — the hosting LiveView must handle both.

  ## Attributes

    * `player` - Player record with rating/win stats
    * `games_data` - List of `{game, game_player}` tuples from `Games.list_player_games/2`
    * `current_page` - Current pagination page (1-indexed)
    * `per_page` - Number of games per page
    * `rating_history` - Rating data points from `Games.get_rating_history/2`
    * `rating_period` - Active rating filter: `:day`, `:month`, `:three_months`, or `:all`
  """
  attr :player, :map, required: true
  attr :games_data, :list, required: true
  attr :current_page, :integer, required: true
  attr :per_page, :integer, required: true
  attr :rating_history, :list, required: true
  attr :rating_period, :atom, required: true

  def game_history_content(assigns) do
    total_pages = max(ceil(length(assigns.games_data) / assigns.per_page), 1)

    paginated_games =
      assigns.games_data
      |> Enum.drop((assigns.current_page - 1) * assigns.per_page)
      |> Enum.take(assigns.per_page)

    assigns =
      assign(assigns,
        paginated_games: paginated_games,
        total_pages: total_pages
      )

    ~H"""
    <div class="space-y-6">
      <!-- Current Rating Display -->
      <div class="stats shadow">
        <div class="stat">
          <div class="stat-title">Current Rating</div>
          <div class="stat-value text-primary">{@player.current_rating}</div>
          <div class="stat-desc">Peak: {@player.peak_rating}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Games Played</div>
          <div class="stat-value">{@player.total_games}</div>
          <div class="stat-desc">{@player.wins}W - {@player.losses}L - {@player.draws}D</div>
        </div>
      </div>
      
    <!-- Rating History Graph -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex justify-between items-center mb-4">
            <h3 class="card-title">Rating History</h3>
            <div class="btn-group">
              <button
                class={["btn btn-sm", @rating_period == :day && "btn-active"]}
                phx-click="filter_rating"
                phx-value-period="day"
              >
                1d
              </button>
              <button
                class={["btn btn-sm", @rating_period == :month && "btn-active"]}
                phx-click="filter_rating"
                phx-value-period="month"
              >
                1m
              </button>
              <button
                class={["btn btn-sm", @rating_period == :three_months && "btn-active"]}
                phx-click="filter_rating"
                phx-value-period="three_months"
              >
                3m
              </button>
              <button
                class={["btn btn-sm", @rating_period == :all && "btn-active"]}
                phx-click="filter_rating"
                phx-value-period="all"
              >
                All
              </button>
            </div>
          </div>

          <.rating_graph history={@rating_history} />
        </div>
      </div>
      
    <!-- Games List -->
      <div class="overflow-x-auto">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th>Game</th>
              <th>Position</th>
              <th>Teammate</th>
              <th>Opponents</th>
              <th>Result</th>
              <th>Rating</th>
            </tr>
          </thead>
          <tbody>
            <%= for {game, game_player} <- @paginated_games do %>
              <.game_row game={game} game_player={game_player} />
            <% end %>
          </tbody>
        </table>
      </div>
      
    <!-- Pagination -->
      <%= if @total_pages > 1 do %>
        <div class="join flex justify-center">
          <%= for page <- 1..@total_pages do %>
            <button
              class={["join-item btn", page == @current_page && "btn-active"]}
              phx-click="change_page"
              phx-value-page={page}
            >
              {page}
            </button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a single game row showing position, players, result, and rating change.
  """
  attr :game, :map, required: true
  attr :game_player, :map, required: true

  def game_row(assigns) do
    # Derive position by matching player_id against the game's position assignments.
    # This is the single source of truth — the game record already holds who sat where.
    position =
      cond do
        assigns.game.board_1_white_id == assigns.game_player.player_id -> "board_1_white"
        assigns.game.board_1_black_id == assigns.game_player.player_id -> "board_1_black"
        assigns.game.board_2_white_id == assigns.game_player.player_id -> "board_2_white"
        assigns.game.board_2_black_id == assigns.game_player.player_id -> "board_2_black"
      end

    position_name =
      case position do
        "board_1_white" -> "Board 1 White"
        "board_1_black" -> "Board 1 Black"
        "board_2_white" -> "Board 2 White"
        "board_2_black" -> "Board 2 Black"
      end

    # Bughouse teams: board_1_white + board_2_black vs board_1_black + board_2_white
    teammate =
      case position do
        "board_1_white" -> assigns.game.board_2_black
        "board_1_black" -> assigns.game.board_2_white
        "board_2_white" -> assigns.game.board_1_black
        "board_2_black" -> assigns.game.board_1_white
      end

    {opp1, opp2} =
      case position do
        "board_1_white" -> {assigns.game.board_1_black, assigns.game.board_2_white}
        "board_1_black" -> {assigns.game.board_1_white, assigns.game.board_2_black}
        "board_2_white" -> {assigns.game.board_1_white, assigns.game.board_2_black}
        "board_2_black" -> {assigns.game.board_1_black, assigns.game.board_2_white}
      end

    result_text =
      if assigns.game_player.won,
        do: "Win",
        else: if(assigns.game_player.outcome == :draw, do: "Draw", else: "Loss")

    result_class =
      if assigns.game_player.won,
        do: "badge-success",
        else: if(assigns.game_player.outcome == :draw, do: "badge-warning", else: "badge-error")

    assigns =
      assign(assigns,
        position_name: position_name,
        teammate: teammate,
        opp1: opp1,
        opp2: opp2,
        result_text: result_text,
        result_class: result_class
      )

    ~H"""
    <tr>
      <td>
        <a href={"/game/view/#{@game.invite_code}"} class="link link-primary">
          {@game.invite_code}
        </a>
      </td>
      <td>{@position_name}</td>
      <td>
        <.player_link player={@teammate} />
      </td>
      <td>
        <div class="flex gap-2">
          <.player_link player={@opp1} />
          <span>&</span>
          <.player_link player={@opp2} />
        </div>
      </td>
      <td>
        <span class={["badge", @result_class]}>
          {@result_text}
        </span>
      </td>
      <td>
        <span class={[
          @game_player.rating_change > 0 && "text-success font-semibold",
          @game_player.rating_change < 0 && "text-error font-semibold"
        ]}>
          {@game_player.rating_after}
          <span class="text-sm">
            ({@game_player.rating_change >= 0 && "+"}
            {@game_player.rating_change})
          </span>
        </span>
      </td>
    </tr>
    """
  end

  @doc """
  Renders a player name as a link to their profile page.
  Guest players display as plain text; nil players show as "unknown".
  """
  attr :player, :any, default: nil

  def player_link(assigns) do
    ~H"""
    <%= if @player do %>
      <%= if @player.guest do %>
        <span class="text-base-content/50">guest</span>
      <% else %>
        <a href={"/player/#{@player.username}"} class="link link-hover">
          {@player.username}
        </a>
      <% end %>
    <% else %>
      <span class="text-base-content/50">unknown</span>
    <% end %>
    """
  end

  @doc """
  Renders a placeholder rating graph visualization.
  """
  attr :history, :list, required: true

  def rating_graph(assigns) do
    ~H"""
    <%= if Enum.empty?(@history) do %>
      <div class="text-center text-base-content/50 py-12">
        No rating history yet. Play some games to see your progress!
      </div>
    <% else %>
      <div class="bg-base-200 rounded-lg p-6 h-64 flex items-center justify-center">
        <div class="text-center">
          <.icon name="hero-chart-bar" class="size-16 mx-auto mb-4 text-primary" />
          <p class="text-base-content/70">
            Rating graph visualization
          </p>
          <p class="text-sm text-base-content/50 mt-2">
            {length(@history)} data points
          </p>
        </div>
      </div>
    <% end %>
    """
  end
end
