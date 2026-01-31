defmodule BughouseWeb.UserAuth do
  @moduledoc """
  Handles guest player creation and session management.

  Provides both a Plug (for initial HTTP requests) and LiveView hooks
  to ensure guest players are created and persisted across page refreshes.
  """

  import Plug.Conn
  import Phoenix.Component
  alias Bughouse.Accounts
  require Logger

  @doc """
  Plug init callback - no options needed.
  """
  def init(opts), do: opts

  @doc """
  Plug that ensures a guest player exists in the session.

  This runs during the initial HTTP request (before LiveView WebSocket upgrade)
  and can modify the session. It creates a guest player if one doesn't exist,
  or validates the existing session player.
  """
  def call(conn, _opts) do
    player =
      case get_session(conn, "current_player_id") do
        nil ->
          Logger.info("Creating new guest player (no session ID found)")
          {:ok, player} = Accounts.create_guest_player()
          Logger.info("Created guest player: #{player.id} (#{player.display_name})")
          player

        player_id ->
          Logger.info("Found session player_id: #{player_id}")

          case Accounts.get_player(player_id) do
            nil ->
              Logger.warning(
                "Session player_id #{player_id} not found in DB, creating new guest"
              )

              {:ok, player} = Accounts.create_guest_player()
              Logger.info("Created replacement guest player: #{player.id} (#{player.display_name})")
              player

            player ->
              Logger.info("Reusing existing guest player: #{player.id} (#{player.display_name})")
              player
          end
      end

    conn
    |> put_session("current_player_id", player.id)
    |> Plug.Conn.assign(:current_player, player)
  end

  @doc """
  LiveView on_mount hook that reads the current player from the session.

  This runs after the Plug has already set the session, so it only needs
  to read the player_id and assign it to the socket.
  """
  def on_mount(:ensure_guest_player, _params, session, socket) do
    require Logger

    player =
      case session["current_player_id"] do
        nil ->
          # This shouldn't happen if the plug ran correctly
          Logger.error("on_mount: No current_player_id in session! Plug may not have run.")
          {:ok, player} = Accounts.create_guest_player()
          player

        player_id ->
          case Accounts.get_player(player_id) do
            nil ->
              Logger.warning("on_mount: Session player #{player_id} not found, creating new")
              {:ok, player} = Accounts.create_guest_player()
              player

            player ->
              player
          end
      end

    socket = Phoenix.Component.assign(socket, :current_player, player)
    {:cont, socket}
  end
end
