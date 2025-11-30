defmodule BughouseWeb.PageController do
  use BughouseWeb, :controller

  def landing(conn, _params) do
    render(conn, :landing)
  end

  def new_game(conn, _params) do
    render(conn, :new_game)
  end

  def create_game(conn, _params) do
    # Generate invite code (same logic as LobbyLive)
    invite_code = generate_invite_code()

    # Redirect to lobby waiting room
    redirect(conn, to: ~p"/lobby/#{invite_code}")
  end

  # Helper function to generate a random invite code
  defp generate_invite_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode16(case: :upper)
  end
end
