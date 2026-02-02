defmodule BughouseWeb.ReplayComponents do
  @moduledoc """
  UI components for the game replay viewer.

  Provides playback controls, progress bar, and other replay-specific components.
  """
  use Phoenix.Component
  import BughouseWeb.CoreComponents

  @doc """
  Renders the replay control bar with play/pause, speed selector, and move indicator.

  ## Attributes

    * `playing` - Boolean indicating if playback is active
    * `speed` - Current playback speed (1.0, 2.0, 3.0, 4.0, or 5.0)
    * `current_move` - Current move index
    * `total_moves` - Total number of moves in the game

  ## Examples

      <.replay_controls
        playing={@playing}
        speed={@playback_speed}
        current_move={@current_move_index}
        total_moves={length(@move_history)}
      />
  """
  attr :playing, :boolean, required: true
  attr :speed, :float, required: true
  attr :current_move, :integer, required: true
  attr :total_moves, :integer, required: true

  def replay_controls(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 bg-base-200 rounded-lg">
      <!-- Play/Pause Button -->
      <button
        id="replay-play-pause"
        class="btn btn-primary btn-lg"
        aria-label={if @playing, do: "Pause", else: "Play"}
      >
        <.icon name={if @playing, do: "hero-pause", else: "hero-play"} class="size-6" />
      </button>

      <!-- Move Indicator -->
      <div class="text-lg font-medium">
        Move <%= @current_move + 1 %> / <%= @total_moves %>
      </div>

      <!-- Speed Selector -->
      <div class="join">
        <%= for speed <- [1.0, 2.0, 3.0, 4.0, 5.0] do %>
          <button
            class={[
              "btn btn-sm join-item",
              @speed == speed && "btn-active btn-primary"
            ]}
            data-action="set-speed"
            data-speed={speed}
            aria-label={"Playback speed #{trunc(speed)}x"}
          >
            <%= trunc(speed) %>x
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders the progress bar with scrubbing capability and move markers.

  ## Attributes

    * `progress` - Current progress percentage (0.0 to 100.0)
    * `move_markers` - List of tuples `{move_num, percent}` for visual markers

  ## Examples

      <.replay_progress_bar
        progress={(@current_move_index / @total_moves) * 100}
        move_markers={generate_move_markers(@move_history)}
      />
  """
  attr :progress, :float, required: true
  attr :move_markers, :list, required: true

  def replay_progress_bar(assigns) do
    ~H"""
    <div
      class="relative w-full h-10 bg-base-300 rounded-lg cursor-pointer group hover:bg-base-200 transition-colors"
      id="replay-progress"
      phx-update="ignore"
      role="slider"
      aria-label="Game progress"
      aria-valuemin="0"
      aria-valuemax="100"
      aria-valuenow={@progress}
    >
      <!-- Progress Fill (updated via JavaScript for smooth interpolation) -->
      <div
        data-progress-fill
        class="absolute top-0 left-0 h-full bg-primary rounded-lg"
        style="width: 0%"
      />

      <!-- Move Markers -->
      <%= for {move_num, percent} <- @move_markers do %>
        <div
          class="absolute top-1/2 -translate-y-1/2 w-0.5 h-5 bg-base-content/40 pointer-events-none"
          style={"left: #{percent}%"}
          title={"Move #{move_num}"}
        />
      <% end %>

      <!-- Current Position Indicator (updated via JavaScript for smooth interpolation) -->
      <div
        data-progress-indicator
        class="absolute top-1/2 -translate-y-1/2 w-4 h-4 bg-white border-2 border-primary rounded-full shadow-lg pointer-events-none"
        style="left: -8px"
      />

      <!-- Hover Indicator (shown when hovering) -->
      <div class="absolute inset-0 opacity-0 group-hover:opacity-20 bg-primary rounded-lg transition-opacity pointer-events-none" />
    </div>
    """
  end
end
