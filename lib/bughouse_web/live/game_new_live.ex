defmodule BughouseWeb.GameNewLive do
  use BughouseWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create New Game")
     |> assign(:time_control, "5")
     |> assign(:game_created, false)
     |> assign(:invite_code, nil)}
  end

  @impl true
  def handle_event("create_game", %{"time_control" => time_control}, socket) do
    # For now, generate a simple invite code
    # In future, this will create a game in the database
    invite_code = generate_invite_code()

    {:noreply,
     socket
     |> assign(:game_created, true)
     |> assign(:invite_code, invite_code)
     |> assign(:time_control, time_control)
     |> put_flash(:info, "Game created successfully! Share the invite code with your friends.")}
  end

  @impl true
  def handle_event("copy_invite_code", _params, socket) do
    {:noreply, put_flash(socket, :info, "Invite code copied to clipboard!")}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(:game_created, false)
     |> assign(:invite_code, nil)
     |> clear_flash()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <%!-- Header --%>
        <div class="text-center mb-12">
          <h1 class="text-4xl font-bold mb-4">
            <.icon name="hero-plus-circle" class="w-10 h-10 inline-block" /> Create New Game
          </h1>
          <p class="text-lg text-base-content/70">
            Set up a new Bughouse chess game and invite your friends
          </p>
        </div>

        <%= if @game_created do %>
          <%!-- Game Created Success State --%>
          <div class="card bg-base-200 shadow-xl">
            <div class="card-body items-center text-center">
              <div class="text-success mb-4">
                <.icon name="hero-check-circle" class="w-20 h-20" />
              </div>

              <h2 class="card-title text-2xl mb-4">Game Created Successfully!</h2>

              <p class="text-base-content/70 mb-6">
                Share this invite code with 3 other players to start the game:
              </p>

              <%!-- Invite Code Display --%>
              <div class="mockup-code bg-base-300 mb-6 w-full max-w-md">
                <pre
                  data-prefix=">"
                  class="text-primary"
                ><code class="text-2xl font-mono font-bold">{@invite_code}</code></pre>
              </div>

              <%!-- Copy Button --%>
              <button
                phx-click="copy_invite_code"
                class="btn btn-primary btn-lg gap-2 mb-4"
                onclick={"navigator.clipboard.writeText('#{@invite_code}')"}
              >
                <.icon name="hero-clipboard-document" class="w-6 h-6" /> Copy Invite Code
              </button>

              <%!-- Game Details --%>
              <div class="stats stats-vertical lg:stats-horizontal shadow mb-6">
                <div class="stat">
                  <div class="stat-figure text-primary">
                    <.icon name="hero-clock" class="w-8 h-8" />
                  </div>
                  <div class="stat-title">Time Control</div>
                  <div class="stat-value text-primary">{@time_control} min</div>
                  <div class="stat-desc">Per player</div>
                </div>

                <div class="stat">
                  <div class="stat-figure text-secondary">
                    <.icon name="hero-user-group" class="w-8 h-8" />
                  </div>
                  <div class="stat-title">Players</div>
                  <div class="stat-value text-secondary">1/4</div>
                  <div class="stat-desc">Waiting for players</div>
                </div>
              </div>

              <%!-- Share Options --%>
              <div class="alert alert-info shadow-lg mb-6">
                <div>
                  <.icon name="hero-information-circle" class="w-6 h-6 flex-shrink-0" />
                  <div>
                    <h3 class="font-bold">How to Share</h3>
                    <p class="text-sm">
                      Send the invite code to your friends via text, email, or your favorite messaging app.
                      They can join by entering the code on the home page.
                    </p>
                  </div>
                </div>
              </div>

              <%!-- Action Buttons --%>
              <div class="card-actions flex-col sm:flex-row gap-4">
                <a href="/lobby/{@invite_code}" class="btn btn-success btn-lg gap-2">
                  <.icon name="hero-arrow-right-circle" class="w-6 h-6" /> Go to Lobby
                </a>
                <button phx-click="reset" class="btn btn-outline btn-lg gap-2">
                  <.icon name="hero-arrow-path" class="w-6 h-6" /> Create Another Game
                </button>
              </div>
            </div>
          </div>
        <% else %>
          <%!-- Game Creation Form --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
            <%!-- Left Column: Form --%>
            <div class="card bg-base-200 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-2xl mb-4">
                  <.icon name="hero-cog-6-tooth" class="w-6 h-6" /> Game Settings
                </h2>

                <form id="create-game-form" phx-submit="create_game" class="space-y-6">
                  <%!-- Time Control --%>
                  <div class="form-control">
                    <label class="label">
                      <span class="label-text font-semibold">
                        <.icon name="hero-clock" class="w-4 h-4 inline-block" />
                        Time Control (minutes per player)
                      </span>
                    </label>
                    <select
                      name="time_control"
                      class="select select-bordered select-primary w-full"
                      value={@time_control}
                    >
                      <option value="1">1 minute - Bullet</option>
                      <option value="3">3 minutes - Blitz</option>
                      <option value="5" selected>5 minutes - Standard</option>
                      <option value="10">10 minutes - Rapid</option>
                      <option value="15">15 minutes - Classical</option>
                      <option value="0">Unlimited - No clock</option>
                    </select>
                    <label class="label">
                      <span class="label-text-alt text-base-content/60">
                        Choose how much time each player gets
                      </span>
                    </label>
                  </div>

                  <%!-- Game Mode Info --%>
                  <div class="alert alert-warning">
                    <div>
                      <.icon name="hero-information-circle" class="w-5 h-5 flex-shrink-0" />
                      <div>
                        <h4 class="font-bold text-sm">Guest Mode</h4>
                        <p class="text-xs">
                          You're creating a guest game. No account required! The game will be
                          available for 24 hours.
                        </p>
                      </div>
                    </div>
                  </div>

                  <%!-- Create Button --%>
                  <div class="card-actions justify-end">
                    <button type="submit" class="btn btn-primary btn-lg w-full gap-2">
                      <.icon name="hero-sparkles" class="w-6 h-6" /> Create Game
                    </button>
                  </div>
                </form>
              </div>
            </div>

            <%!-- Right Column: Info --%>
            <div class="space-y-6">
              <%!-- What Happens Next --%>
              <div class="card bg-gradient-to-br from-primary/10 to-secondary/10 shadow-lg">
                <div class="card-body">
                  <h3 class="card-title text-xl mb-4">
                    <.icon name="hero-question-mark-circle" class="w-6 h-6" /> What happens next?
                  </h3>
                  <ol class="space-y-3 text-base-content/80">
                    <li class="flex items-start gap-3">
                      <span class="badge badge-primary font-bold">1</span>
                      <span>Click "Create Game" to generate a unique invite code</span>
                    </li>
                    <li class="flex items-start gap-3">
                      <span class="badge badge-primary font-bold">2</span>
                      <span>Share the invite code with 3 friends</span>
                    </li>
                    <li class="flex items-start gap-3">
                      <span class="badge badge-primary font-bold">3</span>
                      <span>Wait in the lobby for all players to join</span>
                    </li>
                    <li class="flex items-start gap-3">
                      <span class="badge badge-primary font-bold">4</span>
                      <span>Start playing when all 4 players are ready!</span>
                    </li>
                  </ol>
                </div>
              </div>

              <%!-- Team Setup Info --%>
              <div class="card bg-base-200 shadow-lg">
                <div class="card-body">
                  <h3 class="card-title text-xl mb-4">
                    <.icon name="hero-user-group" class="w-6 h-6" /> Team Setup
                  </h3>
                  <p class="text-base-content/80 mb-4">
                    In Bughouse, players are divided into two teams:
                  </p>
                  <div class="space-y-3">
                    <div class="flex items-center gap-3 p-3 bg-base-300 rounded-lg">
                      <div class="badge badge-lg bg-white text-black font-bold">White Team</div>
                      <span class="text-sm">Player 1 & Player 3</span>
                    </div>
                    <div class="flex items-center gap-3 p-3 bg-base-300 rounded-lg">
                      <div class="badge badge-lg bg-black text-white font-bold">Black Team</div>
                      <span class="text-sm">Player 2 & Player 4</span>
                    </div>
                  </div>
                  <p class="text-sm text-base-content/60 mt-4">
                    Teams will be automatically assigned when players join the lobby.
                  </p>
                </div>
              </div>

              <%!-- Quick Tips --%>
              <div class="card bg-base-200 shadow-lg">
                <div class="card-body">
                  <h3 class="card-title text-xl mb-4">
                    <.icon name="hero-light-bulb" class="w-6 h-6" /> Quick Tips
                  </h3>
                  <ul class="space-y-2 text-sm text-base-content/80">
                    <li class="flex items-start gap-2">
                      <.icon name="hero-check-circle" class="w-4 h-4 mt-1 flex-shrink-0 text-success" />
                      <span>Faster time controls make for more intense games</span>
                    </li>
                    <li class="flex items-start gap-2">
                      <.icon name="hero-check-circle" class="w-4 h-4 mt-1 flex-shrink-0 text-success" />
                      <span>Coordinate with your teammate via chat (coming soon!)</span>
                    </li>
                    <li class="flex items-start gap-2">
                      <.icon name="hero-check-circle" class="w-4 h-4 mt-1 flex-shrink-0 text-success" />
                      <span>Practice makes perfect - start with longer time controls</span>
                    </li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Back to Home --%>
        <div class="text-center mt-12">
          <a href="/" class="btn btn-ghost gap-2">
            <.icon name="hero-arrow-left" class="w-5 h-5" /> Back to Home
          </a>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Helper function to generate invite codes
  defp generate_invite_code do
    # Generate a random 8-character alphanumeric code
    chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    chars_list = String.graphemes(chars)

    1..8
    |> Enum.map(fn _ -> Enum.random(chars_list) end)
    |> Enum.join()
  end
end
