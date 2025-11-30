defmodule BughouseWeb.LobbyLive do
  use BughouseWeb, :live_view

  @impl true
  def mount(%{"invite_code" => code}, _session, socket) do
    {:ok, assign(socket, :invite_code, code)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-100">
      <div class="container mx-auto px-4 py-8">
        <div class="mb-6">
          <a href={~p"/"} class="btn btn-ghost">
            ← Back to Home
          </a>
        </div>

        <div class="max-w-2xl mx-auto">
          <h1 class="text-4xl font-bold mb-8 text-center">Game Lobby</h1>

          <div class="alert alert-success mb-6">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="stroke-current shrink-0 h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span>Game created successfully!</span>
          </div>

          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">Your Game is Ready</h2>
              <p class="mb-4">Share this invite code with your friends:</p>

              <div class="bg-base-300 p-4 rounded-lg text-center">
                <code class="text-2xl font-mono font-bold">{@invite_code}</code>
              </div>

              <div class="mt-4 space-y-2">
                <div class="alert alert-info">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    class="stroke-current shrink-0 w-6 h-6"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <span>Waiting for players to join...</span>
                </div>

                <div class="bg-base-300 p-4 rounded-lg">
                  <h3 class="font-semibold mb-2">Players:</h3>
                  <ul class="space-y-1 text-sm">
                    <li>Player 1 (White, Board A): Waiting...</li>
                    <li>Player 2 (Black, Board A): Waiting...</li>
                    <li>Player 3 (White, Board B): Waiting...</li>
                    <li>Player 4 (Black, Board B): Waiting...</li>
                  </ul>
                </div>
              </div>

              <div class="card-actions justify-end mt-4">
                <button class="btn btn-primary" disabled>
                  Start Game (Coming Soon)
                </button>
              </div>
            </div>
          </div>

          <div class="mt-8">
            <h2 class="text-2xl font-bold mb-4">How to Play Bughouse</h2>
            <div class="space-y-4">
              <div class="collapse collapse-arrow bg-base-200">
                <input type="checkbox" />
                <div class="collapse-title text-lg font-medium">Basic Rules</div>
                <div class="collapse-content">
                  <p>
                    Bughouse is played with four players in two teams of two. Each team has one player
                    on Board A and one on Board B. When you capture a piece, it becomes available for
                    your teammate to place on their board.
                  </p>
                </div>
              </div>

              <div class="collapse collapse-arrow bg-base-200">
                <input type="checkbox" />
                <div class="collapse-title text-lg font-medium">Piece Transfers</div>
                <div class="collapse-content">
                  <p>
                    Captured pieces can be placed (dropped) on any empty square on your teammate's board,
                    except pawns cannot be placed on the 1st or 8th rank.
                  </p>
                </div>
              </div>

              <div class="collapse collapse-arrow bg-base-200">
                <input type="checkbox" />
                <div class="collapse-title text-lg font-medium">Winning Conditions</div>
                <div class="collapse-content">
                  <p>
                    A team wins if either player on the opposing team is checkmated or runs out of time.
                    Both boards are in play simultaneously, creating dynamic and fast-paced gameplay.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
