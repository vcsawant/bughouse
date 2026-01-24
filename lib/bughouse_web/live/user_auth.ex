defmodule BughouseWeb.UserAuth do
  @moduledoc """
  Handles guest player creation for LiveView connections.

  For MVP, creates a new guest player on each connection.
  TODO Phase 2: Add session persistence for guest players.
  """

  import Phoenix.Component
  alias Bughouse.Accounts

  @doc """
  Creates a guest player for the current connection.

  In MVP, a new guest is created each time.  In the future, this will
  check session and reuse existing guests.
  """
  def on_mount(:ensure_guest_player, _params, _session, socket) do
    {:ok, player} = Accounts.create_guest_player()

    socket = assign(socket, :current_player, player)

    {:cont, socket}
  end
end
