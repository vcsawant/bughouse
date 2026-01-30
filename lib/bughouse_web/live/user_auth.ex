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

  Checks session for existing player first. If found, uses that player.
  Otherwise, creates a new guest player.
  """
  def on_mount(:ensure_guest_player, _params, session, socket) do
    player =
      case session["current_player_id"] do
        nil ->
          {:ok, player} = Accounts.create_guest_player()
          player

        player_id ->
          case Accounts.get_player(player_id) do
            nil ->
              {:ok, player} = Accounts.create_guest_player()
              player

            player ->
              player
          end
      end

    socket = assign(socket, :current_player, player)

    {:cont, socket}
  end
end
