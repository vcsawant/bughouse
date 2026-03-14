defmodule BughouseWeb.BotLive do
  use BughouseWeb, :live_view

  alias Bughouse.Bots
  alias Bughouse.Bots.HealthCheck
  alias Bughouse.Schemas.Accounts.Bot

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "My Bots")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    bots = Bots.list_bots_for_owner(socket.assigns.current_player.id)

    socket
    |> assign(:page_title, "My Bots")
    |> assign(:bots, bots)
  end

  defp apply_action(socket, :new, _params) do
    bot = %Bot{
      player_id: socket.assigns.current_player.id,
      bot_type: "internal",
      default_options: %{}
    }

    socket
    |> assign(:page_title, "Register Bot")
    |> assign(:bot, bot)
    |> assign(:form, to_form(Bots.change_bot(bot)))
    |> assign(:selected_preset, "balanced")
    |> assign(:show_custom_options, false)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    bot = Bots.get_bot!(id)

    if bot.player_id != socket.assigns.current_player.id do
      socket
      |> put_flash(:error, "You can only edit your own bots")
      |> push_navigate(to: ~p"/bots")
    else
      preset = detect_preset(bot.default_options)

      socket
      |> assign(:page_title, "Edit Bot")
      |> assign(:bot, bot)
      |> assign(:form, to_form(Bots.change_bot(bot)))
      |> assign(:selected_preset, preset)
      |> assign(:show_custom_options, preset == "custom")
    end
  end

  # Events

  @impl true
  def handle_event("validate", %{"bot" => bot_params}, socket) do
    changeset =
      socket.assigns.bot
      |> Bots.change_bot(bot_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"bot" => bot_params}, socket) do
    bot_params = apply_preset_options(bot_params, socket.assigns.selected_preset)
    save_bot(socket, socket.assigns.live_action, bot_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    bot = Bots.get_bot!(id)

    if bot.player_id == socket.assigns.current_player.id do
      {:ok, _} = Bots.delete_bot(bot)

      {:noreply,
       socket
       |> put_flash(:info, "Bot \"#{bot.display_name}\" deleted")
       |> assign(:bots, Bots.list_bots_for_owner(socket.assigns.current_player.id))}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  def handle_event("select_preset", %{"preset" => preset}, socket) do
    {:noreply,
     socket
     |> assign(:selected_preset, preset)
     |> assign(:show_custom_options, preset == "custom")}
  end

  def handle_event("check_health", %{"id" => id}, socket) do
    bot = Bots.get_bot!(id)
    {:ok, status} = HealthCheck.check(bot)
    {:ok, bot} = Bots.update_health_status(bot, status)

    bots = Bots.list_bots_for_owner(socket.assigns.current_player.id)

    {:noreply,
     socket
     |> assign(:bots, bots)
     |> put_flash(:info, "Health check: #{bot.display_name} is #{status}")}
  end

  # Save helpers

  defp save_bot(socket, :new, bot_params) do
    bot_params = Map.put(bot_params, "player_id", socket.assigns.current_player.id)

    case Bots.create_bot(bot_params) do
      {:ok, bot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bot \"#{bot.display_name}\" registered")
         |> push_navigate(to: ~p"/bots")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_bot(socket, :edit, bot_params) do
    case Bots.update_bot(socket.assigns.bot, bot_params) do
      {:ok, bot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bot \"#{bot.display_name}\" updated")
         |> push_navigate(to: ~p"/bots")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # Preset helpers

  defp apply_preset_options(params, "custom"), do: params

  defp apply_preset_options(params, preset) do
    case Bots.strength_presets()[preset] do
      nil -> params
      options -> Map.put(params, "default_options", options)
    end
  end

  defp detect_preset(options) when options == %{}, do: "balanced"

  defp detect_preset(options) do
    Bots.strength_presets()
    |> Enum.find_value("custom", fn {name, preset_opts} ->
      if preset_opts == options, do: name
    end)
  end

  defp win_rate(bot) do
    if bot.games_played > 0 do
      Float.round(bot.games_won / bot.games_played * 100, 1)
    else
      0.0
    end
  end

  defp health_badge_class("healthy"), do: "badge-success"
  defp health_badge_class("unhealthy"), do: "badge-error"
  defp health_badge_class(_), do: "badge-warning"

  # Template

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-4xl">
      <%= if @live_action == :index do %>
        <.bot_index bots={@bots} />
      <% else %>
        <.bot_form
          form={@form}
          bot={@bot}
          action={@live_action}
          selected_preset={@selected_preset}
          show_custom_options={@show_custom_options}
        />
      <% end %>
    </div>
    """
  end

  # Index view

  defp bot_index(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <h1 class="text-3xl font-bold">My Bots</h1>
      <.link navigate={~p"/bots/new"} class="btn btn-primary">
        Register New Bot
      </.link>
    </div>

    <%= if @bots == [] do %>
      <div class="card bg-base-200">
        <div class="card-body items-center text-center py-16">
          <div class="text-6xl mb-4">🤖</div>
          <h2 class="card-title text-xl">No bots registered yet</h2>
          <p class="text-base-content/60 mb-4">
            Register an AI engine to play bughouse chess automatically.
          </p>
          <.link navigate={~p"/bots/new"} class="btn btn-primary">
            Register Your First Bot
          </.link>
        </div>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Type</th>
              <th>Rating</th>
              <th>Games</th>
              <th>Win Rate</th>
              <th>Health</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={bot <- @bots} class="hover">
              <td>
                <div class="font-bold">{bot.display_name}</div>
                <div class="text-sm opacity-50">@{bot.name}</div>
              </td>
              <td>
                <span class={"badge badge-sm #{if bot.bot_type == "internal", do: "badge-info", else: "badge-accent"}"}>
                  {bot.bot_type}
                </span>
              </td>
              <td class="font-mono">{bot.current_rating}</td>
              <td>{bot.games_played}</td>
              <td>{win_rate(bot)}%</td>
              <td>
                <span class={"badge badge-sm #{health_badge_class(bot.health_status)}"}>
                  {bot.health_status}
                </span>
              </td>
              <td>
                <div class="flex gap-1">
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="check_health"
                    phx-value-id={bot.id}
                    title="Check Health"
                  >
                    <.icon name="hero-heart" class="size-4" />
                  </button>
                  <.link navigate={~p"/bots/#{bot.id}/edit"} class="btn btn-xs btn-ghost">
                    <.icon name="hero-pencil-square" class="size-4" />
                  </.link>
                  <button
                    class="btn btn-xs btn-ghost text-error"
                    phx-click="delete"
                    phx-value-id={bot.id}
                    data-confirm={"Delete bot \"#{bot.display_name}\"? This cannot be undone."}
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  # Form view (new / edit)

  defp bot_form(assigns) do
    ~H"""
    <div class="mb-6">
      <.link navigate={~p"/bots"} class="btn btn-ghost btn-sm gap-1">
        <.icon name="hero-arrow-left" class="size-4" /> Back to Bots
      </.link>
    </div>

    <h1 class="text-3xl font-bold mb-6">
      {if @action == :new, do: "Register New Bot", else: "Edit Bot"}
    </h1>

    <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-6">
      <!-- Bot Identity -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Bot Identity</h2>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Name (unique identifier)</span>
            </label>
            <.input
              field={@form[:name]}
              type="text"
              placeholder="my_bot"
              class="input input-bordered"
            />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Display Name</span>
            </label>
            <.input
              field={@form[:display_name]}
              type="text"
              placeholder="My Awesome Bot"
              class="input input-bordered"
            />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Description</span>
            </label>
            <.input
              field={@form[:description]}
              type="textarea"
              placeholder="A brief description of your bot..."
              class="textarea textarea-bordered"
            />
          </div>
        </div>
      </div>

      <!-- Connection Settings -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Connection</h2>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Bot Type</span>
            </label>
            <div class="flex gap-4">
              <label class="label cursor-pointer gap-2">
                <input
                  type="radio"
                  name={@form[:bot_type].name}
                  value="internal"
                  checked={Phoenix.HTML.Form.input_value(@form, :bot_type) == "internal"}
                  class="radio radio-primary"
                />
                <span class="label-text">Internal (runs on server)</span>
              </label>
              <label class="label cursor-pointer gap-2">
                <input
                  type="radio"
                  name={@form[:bot_type].name}
                  value="external"
                  checked={Phoenix.HTML.Form.input_value(@form, :bot_type) == "external"}
                  class="radio radio-primary"
                />
                <span class="label-text">External (remote connection)</span>
              </label>
            </div>
          </div>

          <%= if Phoenix.HTML.Form.input_value(@form, :bot_type) == "external" do %>
            <div class="form-control">
              <label class="label">
                <span class="label-text">Endpoint Base URL</span>
              </label>
              <.input
                field={@form[:endpoint_base]}
                type="text"
                placeholder="wss://my-bot.example.com"
                class="input input-bordered"
              />
              <label class="label">
                <span class="label-text-alt">
                  WebSocket endpoint for UBI protocol communication
                </span>
              </label>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Engine Settings -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Engine Settings</h2>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Strength Preset</span>
            </label>
            <div class="flex flex-wrap gap-2">
              <button
                :for={preset <- ["fast", "balanced", "strong", "custom"]}
                type="button"
                class={"btn btn-sm #{if @selected_preset == preset, do: "btn-primary", else: "btn-outline"}"}
                phx-click="select_preset"
                phx-value-preset={preset}
              >
                {String.capitalize(preset)}
              </button>
            </div>
            <label class="label">
              <span class="label-text-alt">
                <%= case @selected_preset do %>
                  <% "fast" -> %>
                    1 thread, depth 8, 64 MB hash — quick moves, lower strength
                  <% "balanced" -> %>
                    2 threads, depth 12, 128 MB hash — good balance of speed and strength
                  <% "strong" -> %>
                    4 threads, depth 15, 256 MB hash — strongest play, slower moves
                  <% "custom" -> %>
                    Configure engine options manually
                <% end %>
              </span>
            </label>
          </div>

          <%= if @show_custom_options do %>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-2">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Threads</span>
                </label>
                <input
                  type="number"
                  name="bot[default_options][Threads]"
                  value={@form[:default_options].value["Threads"] || 2}
                  min="1"
                  max="8"
                  class="input input-bordered input-sm"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Depth</span>
                </label>
                <input
                  type="number"
                  name="bot[default_options][Depth]"
                  value={@form[:default_options].value["Depth"] || 12}
                  min="1"
                  max="30"
                  class="input input-bordered input-sm"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Hash (MB)</span>
                </label>
                <input
                  type="number"
                  name="bot[default_options][Hash]"
                  value={@form[:default_options].value["Hash"] || 128}
                  min="16"
                  max="1024"
                  class="input input-bordered input-sm"
                />
              </div>
            </div>
          <% end %>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-2">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Max Concurrent Games</span>
              </label>
              <.input
                field={@form[:max_concurrent_games]}
                type="number"
                min="1"
                max="5"
                class="input input-bordered input-sm"
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text">Move Timeout (seconds)</span>
              </label>
              <.input
                field={@form[:timeout_seconds]}
                type="number"
                min="1"
                max="60"
                class="input input-bordered input-sm"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Visibility -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">Visibility</h2>
          <label class="label cursor-pointer justify-start gap-3">
            <.input field={@form[:is_public]} type="checkbox" class="checkbox checkbox-primary" />
            <div>
              <span class="label-text font-medium">Public Bot</span>
              <p class="text-sm text-base-content/60">
                Public bots appear in the lobby for all players to use
              </p>
            </div>
          </label>
        </div>
      </div>

      <!-- Submit -->
      <div class="flex justify-end gap-2">
        <.link navigate={~p"/bots"} class="btn btn-ghost">Cancel</.link>
        <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
          {if @action == :new, do: "Register Bot", else: "Save Changes"}
        </button>
      </div>
    </.form>
    """
  end
end
