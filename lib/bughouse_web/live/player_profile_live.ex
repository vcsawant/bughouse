defmodule BughouseWeb.PlayerProfileLive do
  @moduledoc """
  Public player profile page at /player/:username.
  Displays the player's stats and game history using shared GameHistoryComponents.
  """
  use BughouseWeb, :live_view
  alias Bughouse.{Accounts, Games}
  alias BughouseWeb.GameHistoryComponents

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_player_by_username(username) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Player not found")
         |> redirect(to: ~p"/")}

      player ->
        games_data = Games.list_player_games(player.id, 100)
        rating_history = Games.get_rating_history(player.id)

        {:ok,
         socket
         |> assign(:player, player)
         |> assign(:games_data, games_data)
         |> assign(:current_page, 1)
         |> assign(:per_page, 25)
         |> assign(:rating_history, rating_history)
         |> assign(:rating_period, :all)}
    end
  end

  @impl true
  def handle_event("change_page", %{"page" => page}, socket) do
    {:noreply, assign(socket, :current_page, String.to_integer(page))}
  end

  def handle_event("filter_rating", %{"period" => period}, socket) do
    period_atom = String.to_existing_atom(period)
    rating_history = Games.get_rating_history(socket.assigns.player.id, period_atom)

    {:noreply,
     socket
     |> assign(:rating_period, period_atom)
     |> assign(:rating_history, rating_history)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-6xl">
      <div class="mb-6">
        <h1 class="text-4xl font-bold">@{@player.username}</h1>
        <p class="text-base-content/70 mt-1">{@player.display_name}</p>
      </div>

      <div class="bg-base-100 border-2 border-base-300 rounded-box p-6">
        <GameHistoryComponents.game_history_content
          player={@player}
          games_data={@games_data}
          current_page={@current_page}
          per_page={@per_page}
          rating_history={@rating_history}
          rating_period={@rating_period}
        />
      </div>
    </div>
    """
  end
end
