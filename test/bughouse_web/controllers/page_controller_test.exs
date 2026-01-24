defmodule BughouseWeb.PageControllerTest do
  use BughouseWeb.ConnCase

  describe "landing page" do
    test "GET / renders landing page with title", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Bughouse Chess"
    end

    test "GET / includes description text", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Experience the excitement of 2v2 chess"
    end

    test "GET / includes create new game link", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Create New Game"
    end

    test "GET / includes feature cards", %{conn: conn} do
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ "Team Play"
      assert response =~ "Piece Transfer"
      assert response =~ "Real-time"
    end
  end

  describe "new game page" do
    test "GET /game/new renders new game form", %{conn: conn} do
      conn = get(conn, ~p"/game/new")
      assert html_response(conn, 200) =~ "Create New Bughouse Game"
    end

    test "GET /game/new includes game setup information", %{conn: conn} do
      conn = get(conn, ~p"/game/new")
      response = html_response(conn, 200)
      assert response =~ "Game Setup"
      assert response =~ "4 Players Required"
    end

    test "GET /game/new includes team setup details", %{conn: conn} do
      conn = get(conn, ~p"/game/new")
      response = html_response(conn, 200)
      assert response =~ "Team Setup"
      assert response =~ "Team 1"
      assert response =~ "Team 2"
      assert response =~ "Partners sit next to each other"
    end

    test "GET /game/new includes create game button", %{conn: conn} do
      conn = get(conn, ~p"/game/new")
      assert html_response(conn, 200) =~ "Create Game"
    end

    test "GET /game/new includes how to play section", %{conn: conn} do
      conn = get(conn, ~p"/game/new")
      response = html_response(conn, 200)
      assert response =~ "How to Play Bughouse"
      assert response =~ "Basic Rules"
    end
  end

  describe "create game" do
    test "POST /game redirects to lobby with invite code", %{conn: conn} do
      conn = post(conn, ~p"/game")
      assert redirected_to(conn) =~ ~p"/lobby/"
    end

    test "POST /game generates a valid invite code format", %{conn: conn} do
      conn = post(conn, ~p"/game")
      redirect_path = redirected_to(conn)
      # Extract invite code from path like "/lobby/ABC12345"
      invite_code = Path.basename(redirect_path)
      # Should be 8 uppercase hex characters
      assert String.length(invite_code) == 8
      assert invite_code =~ ~r/^[0-9A-F]{8}$/
    end

    test "POST /game generates unique invite codes", %{conn: conn} do
      conn1 = post(conn, ~p"/game")
      conn2 = post(conn, ~p"/game")

      code1 = conn1 |> redirected_to() |> Path.basename()
      code2 = conn2 |> redirected_to() |> Path.basename()

      assert code1 != code2
    end
  end
end
