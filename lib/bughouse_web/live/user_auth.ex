defmodule BughouseWeb.UserAuth do
  @moduledoc """
  Handles guest player creation and session management.

  Provides both a Plug (for initial HTTP requests) and LiveView hooks
  to ensure guest players are created and persisted across page refreshes.
  """

  import Plug.Conn
  alias Bughouse.Accounts
  alias Bughouse.Notifications
  require Logger

  @doc """
  Plug init callback - no options needed.
  """
  def init(opts), do: opts

  @doc """
  Plug that ensures a player exists in the session (either authenticated or guest).

  This runs during the initial HTTP request (before LiveView WebSocket upgrade)
  and can modify the session. It creates a guest player if one doesn't exist,
  or validates the existing session player.
  """
  def call(conn, _opts) do
    # Check if user is authenticated (OAuth login)
    if get_session(conn, "authenticated") do
      player_id = get_session(conn, "current_player_id")

      case Accounts.get_player(player_id) do
        nil ->
          # Session invalid, create guest
          create_and_assign_guest(conn)

        player ->
          Logger.info("Authenticated player: #{player.id} (#{player.display_name})")

          conn
          |> put_session("current_player_id", player.id)
          |> assign(:current_player, player)
      end
    else
      # Guest flow (unchanged)
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
                Logger.info("Created replacement guest player: #{player.id}")
                player

              player ->
                Logger.info("Reusing existing player: #{player.id} (#{player.display_name})")
                player
            end
        end

      conn
      |> put_session("current_player_id", player.id)
      |> assign(:current_player, player)
    end
  end

  defp create_and_assign_guest(conn) do
    {:ok, player} = Accounts.create_guest_player()
    Logger.info("Created guest player: #{player.id} (#{player.display_name})")

    conn
    |> configure_session(drop: true)
    |> put_session("current_player_id", player.id)
    |> assign(:current_player, player)
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

  # LiveView hook that requires authenticated (non-guest) users.
  # Redirects to /login if user is guest or not authenticated.
  def on_mount(:require_authenticated, _params, session, socket) do
    alias Bughouse.Schemas.Accounts.Player

    case session["authenticated"] do
      true ->
        player_id = session["current_player_id"]

        case Accounts.get_player(player_id) do
          %Player{guest: false} = player ->
            {:cont, Phoenix.Component.assign(socket, :current_player, player)}

          _ ->
            # Guest or invalid player
            socket =
              socket
              |> Phoenix.LiveView.put_flash(:error, "Please sign in to view your account")
              |> Phoenix.LiveView.redirect(to: "/login")

            {:halt, socket}
        end

      _ ->
        # Not authenticated
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "Please sign in to view your account")
          |> Phoenix.LiveView.redirect(to: "/login")

        {:halt, socket}
    end
  end

  # Subscribes non-guest players to notifications and attaches hooks
  # to handle notification messages and events centrally.
  def on_mount(:subscribe_notifications, _params, _session, socket) do
    player = socket.assigns[:current_player]

    socket = Phoenix.Component.assign(socket, :notifications, [])

    if Phoenix.LiveView.connected?(socket) && player && !player.guest do
      Notifications.subscribe(player.id)

      socket =
        socket
        |> Phoenix.LiveView.attach_hook(:notification_info, :handle_info, fn
          {:notification, notification}, socket ->
            # Schedule auto-dismiss after 10 seconds
            Process.send_after(self(), {:dismiss_notification, notification.id}, 10_000)

            notifications = [notification | socket.assigns.notifications]
            {:halt, Phoenix.Component.assign(socket, :notifications, notifications)}

          {:dismiss_notification, notification_id}, socket ->
            notifications =
              Enum.reject(socket.assigns.notifications, &(&1.id == notification_id))

            {:halt, Phoenix.Component.assign(socket, :notifications, notifications)}

          _other, socket ->
            {:cont, socket}
        end)
        |> Phoenix.LiveView.attach_hook(:notification_event, :handle_event, fn
          "dismiss_notification", %{"id" => notification_id}, socket ->
            notifications =
              Enum.reject(socket.assigns.notifications, &(&1.id == notification_id))

            {:halt, Phoenix.Component.assign(socket, :notifications, notifications)}

          _event, _params, socket ->
            {:cont, socket}
        end)

      {:cont, socket}
    else
      {:cont, socket}
    end
  end
end
