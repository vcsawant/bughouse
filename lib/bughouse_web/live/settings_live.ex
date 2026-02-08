defmodule BughouseWeb.SettingsLive do
  @moduledoc """
  LiveView for user-customizable settings.

  Accessible to all users (guests and authenticated).
  All settings persist via localStorage — no database changes needed.
  """
  use BughouseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-6 max-w-2xl">
      <h1 class="text-2xl font-bold mb-4">Settings</h1>
      
    <!-- Appearance Section -->
      <div class="card bg-base-200 mb-4">
        <div class="card-body p-4 gap-3">
          <h2 class="card-title text-lg">Appearance</h2>

          <div class="flex items-center justify-between">
            <span class="text-sm">App Theme</span>
            <Layouts.theme_toggle />
          </div>

          <div class="divider my-0"></div>

          <div class="flex items-center justify-between">
            <span class="text-sm">Board Theme</span>
            <.chess_board_theme_selector />
          </div>

          <div class="divider my-0"></div>

          <div class="flex justify-center">
            <.chess_board
              fen="r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R"
              size="lg"
              flip={false}
            />
          </div>
        </div>
      </div>
      
    <!-- Clock Section (Future) -->
      <div class="card bg-base-200 mb-4">
        <div class="card-body p-4 gap-2">
          <h2 class="card-title text-lg">Clock</h2>
          <p class="text-sm text-base-content/50">Coming soon.</p>
        </div>
      </div>
    </div>
    """
  end
end
