defmodule BughouseWeb.PageController do
  use BughouseWeb, :controller

  plug :put_layout, html: {BughouseWeb.Layouts, :app}

  def landing(conn, _params) do
    render(conn, :landing)
  end

  def new_game(conn, _params) do
    render(conn, :new_game)
  end

  def create_game(conn, _params) do
    alias Bughouse.Games

    case Games.create_game() do
      {:ok, game} ->
        redirect(conn, to: ~p"/lobby/#{game.invite_code}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to create game. Please try again.")
        |> redirect(to: ~p"/game/new")
    end
  end
end
