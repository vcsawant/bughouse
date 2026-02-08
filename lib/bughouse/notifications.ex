defmodule Bughouse.Notifications do
  @moduledoc """
  PubSub-based notification system for real-time player notifications.

  Each player subscribes to their own topic "player:{player_id}".
  Notifications are broadcast as {:notification, %{...}} messages
  and intercepted by the attach_hook in UserAuth.
  """

  @topic_prefix "player:"

  @doc """
  Subscribes the calling process to notifications for the given player.
  """
  def subscribe(player_id) do
    Phoenix.PubSub.subscribe(Bughouse.PubSub, @topic_prefix <> player_id)
  end

  @doc """
  Sends a lobby invite notification to a player.
  """
  def send_lobby_invite(from_player, to_player_id, invite_code) do
    broadcast(to_player_id, %{
      type: :lobby_invite,
      id: generate_id(),
      from_display_name: from_player.display_name,
      from_id: from_player.id,
      invite_code: invite_code
    })
  end

  @doc """
  Sends a friend request notification to a player.
  """
  def send_friend_request(from_player, to_player_id) do
    broadcast(to_player_id, %{
      type: :friend_request,
      id: generate_id(),
      from_display_name: from_player.display_name,
      from_id: from_player.id
    })
  end

  @doc """
  Sends a "friend request accepted" notification to a player.
  """
  def send_friend_accepted(from_player, to_player_id) do
    broadcast(to_player_id, %{
      type: :friend_accepted,
      id: generate_id(),
      from_display_name: from_player.display_name,
      from_id: from_player.id
    })
  end

  defp broadcast(player_id, notification) do
    Phoenix.PubSub.broadcast(
      Bughouse.PubSub,
      @topic_prefix <> player_id,
      {:notification, notification}
    )
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
