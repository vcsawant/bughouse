defmodule BughouseWeb.TeamCommComponents do
  @moduledoc """
  Components for in-game team communication.

  Renders the quick-comm panel between the two chess boards,
  allowing teammates to send UBI-protocol tactical signals:
  piece requests, stall, hurry, and threat alerts.

  Also renders ephemeral toast notifications for incoming messages.
  """
  use Phoenix.Component

  # --- Main Communication Panel ---

  @doc """
  Collapsible team communication panel rendered between the two boards.

  Shows piece request buttons and tactical signal buttons.
  Only visible to players (not spectators) during an active game.

  ## Attributes

    * `open` - Whether the panel is expanded
    * `my_position` - Current player's board position
  """
  attr :open, :boolean, default: true
  attr :my_position, :atom, required: true

  def team_comm_panel(assigns) do
    ~H"""
    <div class={["flex flex-col items-center gap-3", !@open && "hidden"]}>
      <%!-- Piece Request Buttons --%>
      <div class="flex flex-col items-center gap-1">
        <span class="text-[10px] font-semibold opacity-50 uppercase tracking-widest">Need</span>
        <div class="flex flex-col gap-1">
          <%= for piece <- ~w(q r b n p) do %>
            <button
              type="button"
              class="btn btn-xs btn-ghost btn-square hover:btn-info"
              phx-click="send_team_msg"
              phx-value-type="need"
              phx-value-piece={piece}
              title={"Need #{piece_name(piece)}"}
            >
              <span class="text-lg leading-none">{piece_unicode(piece)}</span>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Tactical Signal Buttons --%>
      <div class="flex flex-col gap-1 w-full">
        <button
          type="button"
          class="btn btn-xs btn-outline btn-warning w-full"
          phx-click="send_team_msg"
          phx-value-type="stall"
          title="Ask teammate to avoid captures"
        >
          Stall
        </button>
        <button
          type="button"
          class="btn btn-xs btn-outline btn-info w-full"
          phx-click="send_team_msg"
          phx-value-type="play_fast"
          title="Ask teammate to move quickly"
        >
          Hurry
        </button>
        <button
          type="button"
          class="btn btn-xs btn-outline btn-error w-full"
          phx-click="send_team_msg"
          phx-value-type="threat"
          phx-value-level="high"
          title="Signal danger on your board"
        >
          Help!
        </button>
      </div>
    </div>
    """
  end

  # --- Message Toast ---

  @doc """
  A single incoming team message displayed as a pill-shaped toast.

  Auto-dismissed after 4 seconds (handled by the LiveView, not this component).

  ## Attributes

    * `message` - The team message map with :type and :params
  """
  attr :message, :map, required: true

  def team_message_toast(assigns) do
    ~H"""
    <div
      class={[
        "flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium shadow-md",
        "animate-slide-in-up whitespace-nowrap",
        toast_bg_class(@message.type)
      ]}
      id={"team-msg-#{@message.id}"}
    >
      <span>{toast_icon(@message)}</span>
      <span>{toast_text(@message)}</span>
    </div>
    """
  end

  # --- Message Feed ---

  @doc """
  Container for up to 3 visible message toasts.

  Absolutely positioned relative to the comm panel so pills don't
  shift the button layout. Direction depends on team:
  - Team 1 (bottom): pills appear below, growing downward
  - Team 2 (top): pills appear above, growing upward

  ## Attributes

    * `messages` - List of team message maps, newest first
    * `my_team` - The current player's team (:team_1 or :team_2)
  """
  attr :messages, :list, default: []
  attr :my_team, :atom, required: true

  def team_message_feed(assigns) do
    ~H"""
    <div class={[
      "absolute left-1/2 -translate-x-1/2 flex items-center gap-1 pointer-events-none z-10",
      feed_position_classes(@my_team)
    ]}>
      <.team_message_toast :for={msg <- Enum.take(@messages, 3)} message={msg} />
    </div>
    """
  end

  defp feed_position_classes(:team_1), do: "top-full mt-1 flex-col"
  defp feed_position_classes(_), do: "bottom-full mb-1 flex-col-reverse"

  # --- Toast Display Helpers ---

  defp toast_icon(%{type: :need, params: %{piece: piece}}), do: piece_unicode(piece)
  defp toast_icon(%{type: :stall}), do: "⏸"
  defp toast_icon(%{type: :play_fast}), do: "⚡"
  defp toast_icon(%{type: :threat}), do: "⚠"
  defp toast_icon(%{type: :material, params: %{value: v}}) when v > 0, do: "📈"
  defp toast_icon(%{type: :material}), do: "📉"

  defp toast_text(%{type: :need, params: %{piece: p}}), do: "Need #{piece_name(p)}!"
  defp toast_text(%{type: :stall}), do: "Stall!"
  defp toast_text(%{type: :play_fast}), do: "Hurry up!"
  defp toast_text(%{type: :threat, params: %{level: level}}), do: "#{format_level(level)} threat!"
  defp toast_text(%{type: :threat}), do: "Help!"
  defp toast_text(%{type: :material, params: %{value: v}}) when v > 0, do: "I'm ahead"
  defp toast_text(%{type: :material}), do: "I'm behind"

  defp toast_bg_class(:need), do: "bg-info text-info-content"
  defp toast_bg_class(:stall), do: "bg-warning text-warning-content"
  defp toast_bg_class(:play_fast), do: "bg-accent text-accent-content"
  defp toast_bg_class(:threat), do: "bg-error text-error-content"
  defp toast_bg_class(:material), do: "bg-base-300 text-base-content"

  defp format_level(level) when is_atom(level) do
    level |> Atom.to_string() |> String.capitalize()
  end

  defp format_level(level) when is_binary(level), do: String.capitalize(level)

  # --- Piece Helpers ---

  defp piece_unicode("q"), do: "♕"
  defp piece_unicode("r"), do: "♖"
  defp piece_unicode("b"), do: "♗"
  defp piece_unicode("n"), do: "♘"
  defp piece_unicode("p"), do: "♙"

  defp piece_name("q"), do: "Queen"
  defp piece_name("r"), do: "Rook"
  defp piece_name("b"), do: "Bishop"
  defp piece_name("n"), do: "Knight"
  defp piece_name("p"), do: "Pawn"
end
