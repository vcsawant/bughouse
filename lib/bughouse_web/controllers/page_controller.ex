defmodule BughouseWeb.PageController do
  use BughouseWeb, :controller

  plug :put_layout, html: {BughouseWeb.Layouts, :app}

  def landing(conn, _params) do
    render(conn, :landing)
  end

  def new_game(conn, _params) do
    render(conn, :new_game)
  end

  @valid_time_controls ~w(1min 2min 5min 10min)

  def create_game(conn, params) do
    alias Bughouse.Games

    time_control =
      if params["time_control"] in @valid_time_controls,
        do: params["time_control"],
        else: "5min"

    case Games.create_game(%{time_control: time_control}) do
      {:ok, game} ->
        redirect(conn, to: ~p"/lobby/#{game.invite_code}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to create game. Please try again.")
        |> redirect(to: ~p"/game/new")
    end
  end
end
