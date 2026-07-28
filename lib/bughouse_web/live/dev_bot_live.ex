defmodule BughouseWeb.DevBotLive do
  @moduledoc """
  Dev-only LiveView for creating and editing internal bots.
  Not available in production.
  """
  use BughouseWeb, :live_view

  alias Bughouse.Bots
  alias Bughouse.Schemas.Accounts.Bot

  @impl true
  def mount(_params, _session, socket) do
    bots = list_internal_bots()
    {:ok, assign(socket, page_title: "Dev Bots", bots: bots, editing: nil, form: nil)}
  end

  @impl true
  def handle_event("new", _params, socket) do
    bot = %Bot{
      owner_id: socket.assigns.current_player.id,
      bot_type: "internal",
      is_public: true,
      is_active: true,
      status: "online",
      default_options: %{}
    }

    form = to_form(Bots.change_bot(bot))
    {:noreply, assign(socket, editing: :new, form: form, bot: bot, options_json: "{}")}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    bot = Bots.get_bot!(id)
    form = to_form(Bots.change_bot(bot))
    options_json = Jason.encode!(bot.default_options || %{})
    {:noreply, assign(socket, editing: id, form: form, bot: bot, options_json: options_json)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: nil)}
  end

  def handle_event("validate", %{"bot" => params}, socket) do
    # Track raw JSON string separately to avoid re-encoding loop
    options_json = Map.get(params, "default_options", socket.assigns.options_json)

    # Parse JSON for the changeset validation, but don't re-encode for display
    parsed_options =
      case Jason.decode(options_json) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    changeset =
      Bots.change_bot(socket.assigns.bot, Map.put(params, "default_options", parsed_options))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset), options_json: options_json)}
  end

  def handle_event("save", %{"bot" => params}, socket) do
    # Parse default_options from JSON string
    parsed_options =
      case Jason.decode(Map.get(params, "default_options", "{}")) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    params =
      params
      |> Map.put("bot_type", "internal")
      |> Map.put("is_public", "true")
      |> Map.put("is_active", "true")
      |> Map.put("status", "online")
      |> Map.put("default_options", parsed_options)

    result =
      case socket.assigns.editing do
        :new ->
          params = Map.put(params, "owner_id", socket.assigns.current_player.id)
          Bots.create_bot(params)

        _id ->
          Bots.update_bot(socket.assigns.bot, params)
      end

    case result do
      {:ok, _bot} ->
        {:noreply,
         socket
         |> assign(editing: nil, form: nil, bots: list_internal_bots())
         |> put_flash(:info, "Bot saved")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    bot = Bots.get_bot!(id)
    {:ok, _} = Bots.delete_bot(bot)

    {:noreply,
     socket
     |> assign(bots: list_internal_bots())
     |> put_flash(:info, "Bot deleted")}
  end

  defp list_internal_bots do
    import Ecto.Query
    Bughouse.Repo.all(from b in Bot, where: b.bot_type == "internal", order_by: b.name)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-3xl">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold">Dev: Internal Bots</h1>
          <p class="text-sm opacity-60">Create and configure internal bots for testing</p>
        </div>
        <%= if @editing == nil do %>
          <button phx-click="new" class="btn btn-primary btn-sm">New Internal Bot</button>
        <% end %>
      </div>

      <%!-- Edit/New Form --%>
      <%= if @form do %>
        <div class="card bg-base-200 p-6 mb-6">
          <h2 class="text-lg font-semibold mb-4">
            {if @editing == :new, do: "New Internal Bot", else: "Edit Bot"}
          </h2>
          <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Name (unique ID)</span></label>
                <input
                  type="text"
                  name="bot[name]"
                  value={@form[:name].value}
                  class="input input-bordered input-sm"
                  placeholder="baseline_stable"
                  required
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Display Name</span></label>
                <input
                  type="text"
                  name="bot[display_name]"
                  value={@form[:display_name].value}
                  class="input input-bordered input-sm"
                  placeholder="Baseline Stable"
                  required
                />
              </div>
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Engine Path (optional — falls back to app config)</span>
              </label>
              <input
                type="text"
                name="bot[engine_path]"
                value={@form[:engine_path].value}
                class="input input-bordered input-sm font-mono"
                placeholder="/path/to/bughouse_engine"
              />
            </div>

            <div class="form-control">
              <label class="label"><span class="label-text">Description</span></label>
              <input
                type="text"
                name="bot[description]"
                value={@form[:description].value}
                class="input input-bordered input-sm"
                placeholder="Stable baseline for benchmarking"
              />
            </div>

            <div class="form-control">
              <label class="label">
                <span class="label-text">Default Options (JSON — sent as UBI setoption)</span>
              </label>
              <input
                type="text"
                name="bot[default_options]"
                value={@options_json}
                class="input input-bordered input-sm font-mono"
                placeholder="{}"
              />
            </div>

            <div class="flex gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
              <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">Cancel</button>
            </div>
          </.form>
        </div>
      <% end %>

      <%!-- Bot List --%>
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>Name</th>
              <th>Display Name</th>
              <th>Engine Path</th>
              <th>Options</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <%= for bot <- @bots do %>
              <tr class="hover">
                <td class="font-mono text-sm">{bot.name}</td>
                <td>{bot.display_name}</td>
                <td class="font-mono text-xs max-w-48 truncate">{bot.engine_path || "(default)"}</td>
                <td class="font-mono text-xs">
                  {if bot.default_options && map_size(bot.default_options) > 0,
                    do: Jason.encode!(bot.default_options),
                    else: "—"}
                </td>
                <td class="flex gap-1">
                  <button phx-click="edit" phx-value-id={bot.id} class="btn btn-ghost btn-xs">
                    Edit
                  </button>
                  <button
                    phx-click="delete"
                    phx-value-id={bot.id}
                    class="btn btn-ghost btn-xs text-error"
                    data-confirm="Delete this bot?"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
