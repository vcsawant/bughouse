defmodule BughouseWeb.BotMatchLive do
  use BughouseWeb, :live_view

  alias Bughouse.{Bots, BotMatches}
  alias Bughouse.Schemas.Games.BotMatch

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Bot Matches")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    matches = BotMatches.list_matches_for_player(socket.assigns.current_player.id)

    socket
    |> assign(:page_title, "Bot Matches")
    |> assign(:matches, matches)
  end

  defp apply_action(socket, :new, _params) do
    my_bots = Bots.list_bots_for_owner(socket.assigns.current_player.id)
    public_bots = Bots.list_public_bots()

    match = %BotMatch{
      created_by_id: socket.assigns.current_player.id,
      total_games: 10,
      time_control_ms: 60_000
    }

    socket
    |> assign(:page_title, "New Bot Match")
    |> assign(:my_bots, my_bots)
    |> assign(:all_bots, merge_bot_lists(my_bots, public_bots))
    |> assign(:match, match)
    |> assign(:form, to_form(BotMatches.change_match(match)))
    |> assign(:selected_games, "10")
    |> assign(:custom_games, "")
    |> assign(:selected_time_control, "60000")
    |> assign(:selected_parallel, "1")
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    match = BotMatches.get_match_with_games(id)

    if match.created_by_id != socket.assigns.current_player.id do
      socket
      |> put_flash(:error, "Match not found")
      |> push_navigate(to: ~p"/matches")
    else
      if connected?(socket) do
        BotMatches.subscribe_to_match(id)
      end

      socket
      |> assign(:page_title, "#{match.bot_a.display_name} vs #{match.bot_b.display_name}")
      |> assign(:match, match)
    end
  end

  ## Events

  @impl true
  def handle_event("validate", %{"bot_match" => params}, socket) do
    changeset =
      BotMatches.change_match(socket.assigns.match, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("select_games", %{"count" => count}, socket) do
    {:noreply, assign(socket, :selected_games, count)}
  end

  def handle_event("update_custom_games", %{"value" => value}, socket) do
    {:noreply, assign(socket, :custom_games, value)}
  end

  def handle_event("select_time_control", %{"ms" => ms}, socket) do
    {:noreply, assign(socket, :selected_time_control, ms)}
  end

  def handle_event("select_parallel", %{"count" => count}, socket) do
    {:noreply, assign(socket, :selected_parallel, count)}
  end

  def handle_event("start_match", %{"bot_match" => params}, socket) do
    total_games = resolve_game_count(socket.assigns.selected_games, socket.assigns.custom_games)
    time_control_ms = String.to_integer(socket.assigns.selected_time_control)
    parallel_games = String.to_integer(socket.assigns.selected_parallel)

    attrs =
      params
      |> Map.put("total_games", total_games)
      |> Map.put("time_control_ms", time_control_ms)
      |> Map.put("parallel_games", parallel_games)
      |> Map.put("created_by_id", socket.assigns.current_player.id)

    case BotMatches.create_match(attrs) do
      {:ok, match} ->
        case BotMatches.start_match(match) do
          {:ok, _match} ->
            {:noreply,
             socket
             |> put_flash(:info, "Bot match started!")
             |> push_navigate(to: ~p"/matches/#{match.id}")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start match")}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("cancel_match", _params, socket) do
    match = socket.assigns.match

    case BotMatches.cancel_match(match) do
      {:ok, match} ->
        {:noreply,
         socket
         |> assign(:match, BotMatches.get_match_with_games(match.id))
         |> put_flash(:info, "Match cancelled")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel match")}
    end
  end

  ## PubSub Handlers

  @impl true
  def handle_info({:match_update, _match}, socket) do
    match = BotMatches.get_match_with_games(socket.assigns.match.id)
    {:noreply, assign(socket, :match, match)}
  end

  def handle_info({:match_completed, _match_id}, socket) do
    match = BotMatches.get_match_with_games(socket.assigns.match.id)

    {:noreply,
     socket
     |> assign(:match, match)
     |> put_flash(:info, "Match completed!")}
  end

  ## Helpers

  defp resolve_game_count("custom", custom) do
    case Integer.parse(custom) do
      {n, _} when n > 0 -> n
      _ -> 10
    end
  end

  defp resolve_game_count(count, _custom), do: String.to_integer(count)

  defp merge_bot_lists(my_bots, public_bots) do
    my_ids = MapSet.new(my_bots, & &1.id)
    public_only = Enum.reject(public_bots, &MapSet.member?(my_ids, &1.id))
    my_bots ++ public_only
  end

  defp status_badge_class("pending"), do: "badge badge-ghost"
  defp status_badge_class("running"), do: "badge badge-info"
  defp status_badge_class("completed"), do: "badge badge-success"
  defp status_badge_class("cancelled"), do: "badge badge-warning"
  defp status_badge_class(_), do: "badge"

  defp result_badge_class("bot_a_win"), do: "badge badge-sm badge-primary"
  defp result_badge_class("bot_b_win"), do: "badge badge-sm badge-secondary"
  defp result_badge_class("draw"), do: "badge badge-sm badge-ghost"
  defp result_badge_class(_), do: "badge badge-sm"

  defp result_label("bot_a_win", match), do: "#{match.bot_a.display_name} wins"
  defp result_label("bot_b_win", match), do: "#{match.bot_b.display_name} wins"
  defp result_label("draw", _match), do: "Draw"
  defp result_label(_, _match), do: "—"

  defp win_rate_percent(wins, total) when total > 0, do: round(wins / total * 100)
  defp win_rate_percent(_, _), do: 0

  defp format_time_control(ms) when ms >= 60_000, do: "#{div(ms, 60_000)}min"
  defp format_time_control(ms), do: "#{div(ms, 1000)}s"

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-5xl">
      <%= case @live_action do %>
        <% :index -> %>
          <.render_index matches={@matches} />
        <% :new -> %>
          <.render_new
            form={@form}
            my_bots={@my_bots}
            all_bots={@all_bots}
            selected_games={@selected_games}
            custom_games={@custom_games}
            selected_time_control={@selected_time_control}
            selected_parallel={@selected_parallel}
          />
        <% :show -> %>
          <.render_show match={@match} />
      <% end %>
    </div>
    """
  end

  ## Index View

  defp render_index(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <h1 class="text-2xl font-bold">Bot Matches</h1>
      <.link navigate={~p"/matches/new"} class="btn btn-primary">
        New Bot Match
      </.link>
    </div>

    <%= if Enum.empty?(@matches) do %>
      <div class="card bg-base-200 p-12 text-center">
        <p class="text-lg opacity-60 mb-4">No matches yet</p>
        <p class="text-sm opacity-40">
          Create a bot match to pit two engines against each other
        </p>
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>Match</th>
              <th>Score</th>
              <th>Progress</th>
              <th>Time Control</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <%= for match <- @matches do %>
              <tr class="hover">
                <td class="font-medium">
                  {match.bot_a.display_name} vs {match.bot_b.display_name}
                </td>
                <td>
                  <span class="font-mono">
                    {match.bot_a_wins} - {match.draws} - {match.bot_b_wins}
                  </span>
                </td>
                <td>
                  <span class="font-mono">{match.completed_games}/{match.total_games}</span>
                </td>
                <td>{format_time_control(match.time_control_ms)}</td>
                <td>
                  <span class={status_badge_class(match.status)}>{match.status}</span>
                </td>
                <td>
                  <.link navigate={~p"/matches/#{match.id}"} class="btn btn-ghost btn-xs">
                    View
                  </.link>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  ## New Match View

  defp render_new(assigns) do
    ~H"""
    <div class="mb-6">
      <.link navigate={~p"/matches"} class="btn btn-ghost btn-sm">
        &larr; Back to matches
      </.link>
    </div>

    <h1 class="text-2xl font-bold mb-6">New Bot Match</h1>

    <.form for={@form} phx-submit="start_match" phx-change="validate" class="space-y-6 max-w-xl">
      <%!-- Bot Selection --%>
      <div class="card bg-base-200 p-6">
        <h3 class="text-lg font-semibold mb-4">Competitors</h3>

        <div class="form-control mb-4">
          <label class="label"><span class="label-text font-medium">Bot A</span></label>
          <select name="bot_match[bot_a_id]" class="select select-bordered w-full" required>
            <option value="">Select a bot...</option>
            <%= for bot <- @my_bots do %>
              <option value={bot.id}>{bot.display_name} ({bot.name})</option>
            <% end %>
          </select>
        </div>

        <div class="form-control">
          <label class="label"><span class="label-text font-medium">Bot B</span></label>
          <select name="bot_match[bot_b_id]" class="select select-bordered w-full" required>
            <option value="">Select an opponent...</option>
            <%= for bot <- @all_bots do %>
              <option value={bot.id}>{bot.display_name} ({bot.name})</option>
            <% end %>
          </select>
        </div>
      </div>

      <%!-- Game Count --%>
      <div class="card bg-base-200 p-6">
        <h3 class="text-lg font-semibold mb-4">Number of Games</h3>
        <div class="flex flex-wrap gap-2 mb-3">
          <%= for count <- ["1", "10", "50", "100"] do %>
            <button
              type="button"
              phx-click="select_games"
              phx-value-count={count}
              class={[
                "btn btn-sm",
                if(@selected_games == count, do: "btn-primary", else: "btn-outline")
              ]}
            >
              {count}
            </button>
          <% end %>
          <button
            type="button"
            phx-click="select_games"
            phx-value-count="custom"
            class={[
              "btn btn-sm",
              if(@selected_games == "custom", do: "btn-primary", else: "btn-outline")
            ]}
          >
            Custom
          </button>
        </div>
        <%= if @selected_games == "custom" do %>
          <input
            type="number"
            min="1"
            max="1000"
            value={@custom_games}
            phx-keyup="update_custom_games"
            class="input input-bordered w-32"
            placeholder="e.g. 25"
          />
        <% end %>
      </div>

      <%!-- Parallel Games --%>
      <div class="card bg-base-200 p-6">
        <h3 class="text-lg font-semibold mb-4">Parallel Games</h3>
        <p class="text-sm opacity-60 mb-3">Run multiple games simultaneously to speed up the match</p>
        <div class="flex gap-2">
          <%= for count <- ["1", "2", "3", "5"] do %>
            <button
              type="button"
              phx-click="select_parallel"
              phx-value-count={count}
              class={[
                "btn btn-sm",
                if(@selected_parallel == count, do: "btn-primary", else: "btn-outline")
              ]}
            >
              {count}
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Time Control --%>
      <div class="card bg-base-200 p-6">
        <h3 class="text-lg font-semibold mb-4">Time Control</h3>
        <div class="flex gap-2">
          <%= for {label, ms} <- [{"1 min", "60000"}, {"3 min", "180000"}, {"5 min", "300000"}] do %>
            <button
              type="button"
              phx-click="select_time_control"
              phx-value-ms={ms}
              class={[
                "btn btn-sm",
                if(@selected_time_control == ms, do: "btn-primary", else: "btn-outline")
              ]}
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>

      <button type="submit" class="btn btn-primary btn-lg w-full">
        Start Bot Match
      </button>
    </.form>
    """
  end

  ## Show View

  defp render_show(assigns) do
    ~H"""
    <div class="mb-6">
      <.link navigate={~p"/matches"} class="btn btn-ghost btn-sm">
        &larr; Back to matches
      </.link>
    </div>

    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold">
          {@match.bot_a.display_name} vs {@match.bot_b.display_name}
        </h1>
        <div class="flex items-center gap-3 mt-1">
          <span class={status_badge_class(@match.status)}>{@match.status}</span>
          <span class="text-sm opacity-60">
            {format_time_control(@match.time_control_ms)} per player
          </span>
        </div>
      </div>

      <%= if @match.status == "running" do %>
        <button
          phx-click="cancel_match"
          class="btn btn-outline btn-error btn-sm"
          data-confirm="Cancel this match?"
        >
          Cancel Match
        </button>
      <% end %>
    </div>

    <%!-- Score --%>
    <div class="card bg-base-200 p-6 mb-6">
      <div class="flex items-center justify-between mb-4">
        <div class="text-center flex-1">
          <div class="text-lg font-bold">{@match.bot_a.display_name}</div>
          <div class="text-3xl font-mono font-bold text-primary">{@match.bot_a_wins}</div>
        </div>
        <div class="text-center px-4">
          <div class="text-sm opacity-60">draws</div>
          <div class="text-2xl font-mono">{@match.draws}</div>
        </div>
        <div class="text-center flex-1">
          <div class="text-lg font-bold">{@match.bot_b.display_name}</div>
          <div class="text-3xl font-mono font-bold text-secondary">{@match.bot_b_wins}</div>
        </div>
      </div>

      <%!-- Win rate bar --%>
      <%= if @match.completed_games > 0 do %>
        <div class="flex h-4 rounded-full overflow-hidden bg-base-300">
          <div
            class="bg-primary"
            style={"width: #{win_rate_percent(@match.bot_a_wins, @match.completed_games)}%"}
          >
          </div>
          <div
            class="bg-base-content bg-opacity-20"
            style={"width: #{win_rate_percent(@match.draws, @match.completed_games)}%"}
          >
          </div>
          <div
            class="bg-secondary"
            style={"width: #{win_rate_percent(@match.bot_b_wins, @match.completed_games)}%"}
          >
          </div>
        </div>
        <div class="flex justify-between mt-1 text-xs opacity-60">
          <span>{win_rate_percent(@match.bot_a_wins, @match.completed_games)}%</span>
          <span>{@match.completed_games}/{@match.total_games} games</span>
          <span>{win_rate_percent(@match.bot_b_wins, @match.completed_games)}%</span>
        </div>
      <% else %>
        <div class="text-center text-sm opacity-60">No games completed yet</div>
      <% end %>
    </div>

    <%!-- Current game link --%>
    <%= if @match.status == "running" and @match.current_game do %>
      <div class="alert alert-info mb-6">
        <span>
          Game {@match.completed_games + 1} of {@match.total_games} in progress
        </span>
        <.link navigate={~p"/game/#{@match.current_game.invite_code}"} class="btn btn-sm btn-ghost">
          Watch Live
        </.link>
      </div>
    <% end %>

    <%!-- Game Results Table --%>
    <%= if length(@match.bot_match_games) > 0 do %>
      <h2 class="text-lg font-semibold mb-3">Game Results</h2>
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>#</th>
              <th>Result</th>
              <th>{@match.bot_a.display_name} played as</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <%= for game <- @match.bot_match_games do %>
              <tr>
                <td class="font-mono">{game.game_number}</td>
                <td>
                  <span class={result_badge_class(game.result)}>
                    {result_label(game.result, @match)}
                  </span>
                </td>
                <td class="text-sm opacity-70">{game.bot_a_team}</td>
                <td>
                  <.link
                    navigate={~p"/game/view/#{game.game.invite_code}"}
                    class="btn btn-ghost btn-xs"
                  >
                    Replay
                  </.link>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end
end
