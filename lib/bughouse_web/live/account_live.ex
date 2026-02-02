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
     |> assign(:display_name_form, to_form(%{"display_name" => player.display_name}))}
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
          <.friends_tab />
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
    <div class="text-center py-12">
      <.icon name="hero-user-group" class="size-20 mx-auto mb-4 text-base-content/30" />
      <h2 class="text-3xl font-bold text-base-content/70">COMING SOON</h2>
      <p class="mt-4 text-base-content/50">
        Friend management features will be available in a future update.
      </p>
    </div>
    """
  end
end
