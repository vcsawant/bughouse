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
        current = socket.assigns.current_player
        games_data = Games.list_player_games(player.id, 100)
        rating_history = Games.get_rating_history(player.id)

        friendship_status =
          if current.guest do
            :none
          else
            Accounts.get_friendship_status(current.id, player.id)
          end

        {:ok,
         socket
         |> assign(:player, player)
         |> assign(:games_data, games_data)
         |> assign(:current_page, 1)
         |> assign(:per_page, 25)
         |> assign(:rating_history, rating_history)
         |> assign(:rating_period, :all)
         |> assign(:friendship_status, friendship_status)
         |> assign(:is_self, current.id == player.id)}
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

  def handle_event("add_friend", _params, socket) do
    current = socket.assigns.current_player
    player = socket.assigns.player

    case Accounts.create_friendship(current.id, player.id) do
      {:ok, _} ->
        Bughouse.Notifications.send_friend_request(current, player.id)

        {:noreply,
         socket
         |> assign(:friendship_status, :pending_sent)
         |> put_flash(:info, "Friend request sent to #{player.display_name}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not send friend request")}
    end
  end

  def handle_event("cancel_request", _params, socket) do
    current = socket.assigns.current_player
    player = socket.assigns.player

    case Accounts.cancel_friendship(current.id, player.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:friendship_status, :none)
         |> put_flash(:info, "Friend request cancelled")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not cancel request")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-6xl">
      <div class="mb-6">
        <div class="flex items-center gap-3 flex-wrap">
          <h1 class="text-4xl font-bold">@{@player.username}</h1>
          <span :if={@player.is_bot} class="badge badge-accent gap-1">
            <.icon name="hero-cpu-chip" class="size-4" /> Bot
          </span>
          <span :if={@friendship_status == :friends} class="badge badge-success gap-1">
            <.icon name="hero-user-group" class="size-4" /> Friend
          </span>
        </div>
        <p class="text-base-content/70 mt-1">{@player.display_name}</p>
        
    <!-- Contextual friend button -->
        <div class="mt-3">
          <%= if !@is_self and !@current_player.guest and !@player.is_bot do %>
            <%= case @friendship_status do %>
              <% :none -> %>
                <button class="btn btn-primary btn-sm" phx-click="add_friend">
                  <.icon name="hero-user-plus" class="size-4" /> Add Friend
                </button>
              <% :pending_sent -> %>
                <button class="btn btn-ghost btn-sm" phx-click="cancel_request">
                  <.icon name="hero-clock" class="size-4" /> Request Sent
                </button>
              <% :pending_received -> %>
                <span class="badge badge-warning gap-1">
                  <.icon name="hero-user-plus" class="size-4" /> Wants to be friends
                </span>
              <% :friends -> %>
              <% _ -> %>
            <% end %>
          <% end %>
        </div>
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
