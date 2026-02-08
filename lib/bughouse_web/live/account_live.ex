defmodule BughouseWeb.AccountLive do
  use BughouseWeb, :live_view
  alias Bughouse.{Accounts, Games}
  alias BughouseWeb.GameHistoryComponents

  @impl true
  def mount(_params, _session, socket) do
    player = socket.assigns.current_player

    # Load player with OAuth identities
    player = Accounts.get_player_with_identities(player.id)

    # Load game history (100 games max)
    games_data = Games.list_player_games(player.id, 100)

    # Load rating history (default: all time)
    rating_history = Games.get_rating_history(player.id)

    # Load friends data
    friends_with_stats = Accounts.get_friends_with_stats(player.id)
    pending_requests = Accounts.get_pending_requests(player.id)
    sent_requests = Accounts.get_sent_requests(player.id)

    {:ok,
     socket
     |> assign(:player, player)
     |> assign(:active_tab, :profile)
     |> assign(:games_data, games_data)
     |> assign(:current_page, 1)
     |> assign(:per_page, 25)
     |> assign(:rating_history, rating_history)
     |> assign(:rating_period, :all)
     |> assign(:editing_display_name, false)
     |> assign(:display_name_form, to_form(%{"display_name" => player.display_name}))
     |> assign(:friends_with_stats, friends_with_stats)
     |> assign(:pending_requests, pending_requests)
     |> assign(:sent_requests, sent_requests)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("edit_display_name", _params, socket) do
    {:noreply, assign(socket, :editing_display_name, true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_display_name, false)
     |> assign(
       :display_name_form,
       to_form(%{"display_name" => socket.assigns.player.display_name})
     )}
  end

  def handle_event("save_display_name", %{"display_name" => display_name}, socket) do
    case Accounts.update_player_display_name(socket.assigns.player, display_name) do
      {:ok, updated_player} ->
        {:noreply,
         socket
         |> assign(:player, updated_player)
         |> assign(:editing_display_name, false)
         |> put_flash(:info, "Display name updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update display name")}
    end
  end

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

  def handle_event("search_players", %{"query" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Accounts.search_players(query, socket.assigns.player.id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  def handle_event("accept_friend", %{"id" => requester_id}, socket) do
    player = socket.assigns.player

    case Accounts.accept_friendship(player.id, requester_id) do
      {:ok, _} ->
        requester = Accounts.get_player!(requester_id)
        Bughouse.Notifications.send_friend_accepted(player, requester_id)

        {:noreply,
         socket
         |> put_flash(:info, "You are now friends with #{requester.display_name}")
         |> reload_friends_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not accept request")}
    end
  end

  def handle_event("reject_friend", %{"id" => requester_id}, socket) do
    case Accounts.reject_friendship(socket.assigns.player.id, requester_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Friend request declined")
         |> reload_friends_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not decline request")}
    end
  end

  def handle_event("remove_friend", %{"id" => friend_id}, socket) do
    case Accounts.remove_friendship(socket.assigns.player.id, friend_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Friend removed")
         |> reload_friends_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove friend")}
    end
  end

  defp reload_friends_data(socket) do
    player_id = socket.assigns.player.id

    socket
    |> assign(:friends_with_stats, Accounts.get_friends_with_stats(player_id))
    |> assign(:pending_requests, Accounts.get_pending_requests(player_id))
    |> assign(:sent_requests, Accounts.get_sent_requests(player_id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-6xl">
      <h1 class="text-4xl font-bold mb-8">Account</h1>
      
    <!-- Tabs Navigation -->
      <div role="tablist" class="tabs tabs-lifted mb-6">
        <button
          role="tab"
          class={["tab", @active_tab == :profile && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="profile"
        >
          Profile
        </button>
        <button
          role="tab"
          class={["tab", @active_tab == :game_history && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="game_history"
        >
          Game History
        </button>
        <button
          role="tab"
          class={["tab", @active_tab == :friends && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="friends"
        >
          Friends
        </button>
      </div>
      
    <!-- Tab Content -->
      <div class="bg-base-100 border-2 border-base-300 rounded-box p-6">
        <%= if @active_tab == :profile do %>
          <.profile_tab player={@player} editing={@editing_display_name} form={@display_name_form} />
        <% end %>

        <%= if @active_tab == :game_history do %>
          <GameHistoryComponents.game_history_content
            player={@player}
            games_data={@games_data}
            current_page={@current_page}
            per_page={@per_page}
            rating_history={@rating_history}
            rating_period={@rating_period}
          />
        <% end %>

        <%= if @active_tab == :friends do %>
          <.friends_tab
            friends_with_stats={@friends_with_stats}
            pending_requests={@pending_requests}
            sent_requests={@sent_requests}
            search_query={@search_query}
            search_results={@search_results}
          />
        <% end %>
      </div>
    </div>
    """
  end

  # Profile Tab Component
  defp profile_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <h2 class="text-2xl font-bold">Profile Information</h2>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <!-- Display Name (Editable) -->
        <div class="form-control">
          <label class="label">
            <span class="label-text font-semibold">Display Name</span>
          </label>
          <%= if @editing do %>
            <.form for={@form} phx-submit="save_display_name" class="flex gap-2">
              <input
                type="text"
                name="display_name"
                value={Phoenix.HTML.Form.input_value(@form, :display_name)}
                class="input input-bordered flex-1"
                placeholder="Enter display name"
                required
              />
              <button type="submit" class="btn btn-primary">Save</button>
              <button type="button" class="btn btn-ghost" phx-click="cancel_edit">Cancel</button>
            </.form>
          <% else %>
            <div class="flex items-center gap-2">
              <span class="text-lg">{@player.display_name}</span>
              <button class="btn btn-sm btn-ghost" phx-click="edit_display_name">
                <.icon name="hero-pencil" class="size-4" />
              </button>
            </div>
          <% end %>
        </div>
        
    <!-- Username (Read-only) -->
        <div class="form-control">
          <label class="label">
            <span class="label-text font-semibold">Username</span>
          </label>
          <span class="text-lg">@{@player.username}</span>
        </div>
        
    <!-- Email (Read-only) -->
        <div class="form-control">
          <label class="label">
            <span class="label-text font-semibold">Email</span>
          </label>
          <span class="text-lg">{@player.email}</span>
        </div>
        
    <!-- Created At (Read-only) -->
        <div class="form-control">
          <label class="label">
            <span class="label-text font-semibold">Member Since</span>
          </label>
          <span class="text-lg">
            {Calendar.strftime(@player.inserted_at, "%B %d, %Y")}
          </span>
        </div>
      </div>
      
    <!-- OAuth Identities -->
      <div class="mt-6">
        <h3 class="text-xl font-semibold mb-3">Connected Accounts</h3>
        <div class="flex flex-wrap gap-3">
          <%= for identity <- @player.user_identities do %>
            <div class="badge badge-lg badge-primary gap-2">
              <.icon :if={identity.provider == "google"} name="hero-globe-alt" class="size-4" />
              {String.capitalize(identity.provider)}
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Friends Tab Component
  defp friends_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <h2 class="text-2xl font-bold">Friends</h2>
      
    <!-- Search Bar -->
      <div class="form-control">
        <label class="label">
          <span class="label-text font-semibold">Find Players</span>
        </label>
        <input
          type="text"
          placeholder="Search by username or display name..."
          value={@search_query}
          phx-keyup="search_players"
          phx-value-query={@search_query}
          phx-debounce="300"
          class="input input-bordered w-full max-w-md"
        />
        <%= if @search_results != [] do %>
          <div class="mt-2 bg-base-200 rounded-lg p-2 max-w-md">
            <div
              :for={player <- @search_results}
              class="flex items-center justify-between py-2 px-3 hover:bg-base-300 rounded"
            >
              <.link navigate={"/player/#{player.username}"} class="link link-hover font-medium">
                {player.display_name}
                <span class="text-sm opacity-60">@{player.username}</span>
              </.link>
            </div>
          </div>
        <% end %>
        <%= if @search_query != "" and String.length(@search_query) >= 2 and @search_results == [] do %>
          <p class="text-sm opacity-50 mt-2">No players found</p>
        <% end %>
      </div>
      
    <!-- Pending Requests (Incoming) -->
      <%= if @pending_requests != [] do %>
        <div>
          <h3 class="text-lg font-semibold mb-3">
            Friend Requests
            <span class="badge badge-primary badge-sm ml-1">{length(@pending_requests)}</span>
          </h3>
          <div class="space-y-2">
            <div
              :for={request <- @pending_requests}
              class="flex items-center justify-between bg-base-200 rounded-lg p-3"
            >
              <div class="flex items-center gap-3">
                <.icon name="hero-user-plus" class="size-5 text-info" />
                <div>
                  <.link
                    navigate={"/player/#{request.player.username}"}
                    class="font-semibold link link-hover"
                  >
                    {request.player.display_name}
                  </.link>
                  <span class="text-sm opacity-60 ml-1">@{request.player.username}</span>
                </div>
              </div>
              <div class="flex gap-2">
                <button
                  class="btn btn-success btn-sm"
                  phx-click="accept_friend"
                  phx-value-id={request.player.id}
                >
                  Accept
                </button>
                <button
                  class="btn btn-ghost btn-sm"
                  phx-click="reject_friend"
                  phx-value-id={request.player.id}
                >
                  Decline
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
      
    <!-- Sent Requests (Outgoing) -->
      <%= if @sent_requests != [] do %>
        <div>
          <h3 class="text-lg font-semibold mb-3">Sent Requests</h3>
          <div class="space-y-2">
            <div
              :for={request <- @sent_requests}
              class="flex items-center justify-between bg-base-200 rounded-lg p-3"
            >
              <div class="flex items-center gap-3">
                <.icon name="hero-clock" class="size-5 text-warning" />
                <div>
                  <.link
                    navigate={"/player/#{request.friend.username}"}
                    class="font-semibold link link-hover"
                  >
                    {request.friend.display_name}
                  </.link>
                  <span class="text-sm opacity-60 ml-1">@{request.friend.username}</span>
                </div>
              </div>
              <span class="badge badge-warning badge-sm">Pending</span>
            </div>
          </div>
        </div>
      <% end %>
      
    <!-- Friends List with Stats -->
      <%= if @friends_with_stats != [] do %>
        <div>
          <h3 class="text-lg font-semibold mb-3">
            Your Friends <span class="badge badge-sm ml-1">{length(@friends_with_stats)}</span>
          </h3>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Player</th>
                  <th class="text-center">Total Games</th>
                  <th class="text-center">Wins With</th>
                  <th class="text-center">Wins Against</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={%{friend: friend} = entry <- @friends_with_stats}>
                  <td>
                    <.link
                      navigate={"/player/#{friend.username}"}
                      class="font-semibold link link-hover"
                    >
                      {friend.display_name}
                    </.link>
                    <span class="text-sm opacity-60 ml-1">@{friend.username}</span>
                  </td>
                  <td class="text-center">{entry.total_games}</td>
                  <td class="text-center text-success font-semibold">{entry.wins_with}</td>
                  <td class="text-center text-warning font-semibold">{entry.wins_against}</td>
                  <td class="text-right">
                    <button
                      class="btn btn-ghost btn-xs text-error"
                      phx-click="remove_friend"
                      phx-value-id={friend.id}
                      data-confirm="Remove #{friend.display_name} from your friends?"
                    >
                      Remove
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      <% else %>
        <%= if @pending_requests == [] and @sent_requests == [] do %>
          <div class="text-center py-8">
            <.icon name="hero-user-group" class="size-16 mx-auto mb-4 text-base-content/30" />
            <p class="text-base-content/50">
              No friends yet. Search for players above to add friends!
            </p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
