defmodule BughouseWeb.NotificationComponents do
  @moduledoc """
  Toast notification components rendered in the app layout.
  Handles lobby invites, friend requests, and friend accepted notifications.
  """
  use Phoenix.Component
  import BughouseWeb.CoreComponents, only: [icon: 1]

  attr :notifications, :list, default: []

  def notification_toasts(assigns) do
    ~H"""
    <div class="fixed top-4 right-4 z-50 flex flex-col gap-2 max-w-sm">
      <div
        :for={notification <- @notifications}
        class="alert shadow-lg animate-slide-in-right"
        id={"notification-#{notification.id}"}
      >
        <.notification_body notification={notification} />
        <button
          class="btn btn-sm btn-ghost btn-circle"
          phx-click="dismiss_notification"
          phx-value-id={notification.id}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  defp notification_body(%{notification: %{type: :lobby_invite}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <.icon name="hero-puzzle-piece" class="size-6 text-primary" />
      <div>
        <p class="font-semibold text-sm">{@notification.from_display_name}</p>
        <p class="text-xs opacity-70">invited you to a game</p>
      </div>
      <.link
        navigate={"/lobby/#{@notification.invite_code}"}
        class="btn btn-primary btn-xs"
      >
        Join
      </.link>
    </div>
    """
  end

  defp notification_body(%{notification: %{type: :friend_request}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <.icon name="hero-user-plus" class="size-6 text-info" />
      <div>
        <p class="font-semibold text-sm">{@notification.from_display_name}</p>
        <p class="text-xs opacity-70">sent you a friend request</p>
      </div>
      <.link navigate="/account" class="btn btn-info btn-xs">
        View
      </.link>
    </div>
    """
  end

  defp notification_body(%{notification: %{type: :friend_accepted}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <.icon name="hero-user-group" class="size-6 text-success" />
      <div>
        <p class="font-semibold text-sm">{@notification.from_display_name}</p>
        <p class="text-xs opacity-70">accepted your friend request</p>
      </div>
    </div>
    """
  end

  defp notification_body(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <.icon name="hero-bell" class="size-6" />
      <p class="text-sm">New notification</p>
    </div>
    """
  end
end
