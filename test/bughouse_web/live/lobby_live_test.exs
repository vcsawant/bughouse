defmodule BughouseWeb.LobbyLiveTest do
  use BughouseWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "lobby waiting room" do
    test "mounts successfully with invite code", %{conn: conn} do
      invite_code = "ABC12345"
      {:ok, _view, html} = live(conn, ~p"/lobby/#{invite_code}")
      assert html =~ "Game Lobby"
    end

    test "displays the invite code from URL params", %{conn: conn} do
      invite_code = "TEST1234"
      {:ok, _view, html} = live(conn, ~p"/lobby/#{invite_code}")
      assert html =~ invite_code
    end

    test "shows game created success message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      assert html =~ "Game created successfully!"
    end

    test "displays invite code sharing instructions", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      assert html =~ "Share this invite code with your friends"
    end

    test "shows waiting for players message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      assert html =~ "Waiting for players to join"
    end

    test "displays all four player slots", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      assert html =~ "Player 1"
      assert html =~ "Player 2"
      assert html =~ "Player 3"
      assert html =~ "Player 4"
    end

    test "shows player team assignments", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      assert html =~ "White, Board A"
      assert html =~ "Black, Board A"
      assert html =~ "White, Board B"
      assert html =~ "Black, Board B"
    end

    test "includes how to play section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      assert html =~ "How to Play Bughouse"
      assert html =~ "Basic Rules"
      assert html =~ "Piece Transfers"
      assert html =~ "Winning Conditions"
    end

    test "displays start game button (disabled)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      assert html =~ "Start Game"
      assert html =~ "Coming Soon"
    end

    test "includes back to home link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      assert html =~ "Back to Home"
    end
  end

  describe "invite code handling" do
    test "accepts various invite code formats", %{conn: conn} do
      codes = ["ABC123", "12345678", "TESTCODE", "A1B2C3D4"]

      for code <- codes do
        {:ok, view, _html} = live(conn, ~p"/lobby/#{code}")
        # Verify the code is stored in socket assigns
        assert render(view) =~ code
      end
    end

    test "renders different invite codes independently", %{conn: conn} do
      {:ok, view1, _html} = live(conn, ~p"/lobby/CODE1111")
      {:ok, view2, _html} = live(conn, ~p"/lobby/CODE2222")

      assert render(view1) =~ "CODE1111"
      assert render(view2) =~ "CODE2222"
      refute render(view1) =~ "CODE2222"
      refute render(view2) =~ "CODE1111"
    end
  end

  describe "page structure" do
    test "uses proper semantic HTML with heading", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      # Check for h1 with title
      assert html =~ "<h1"
      assert html =~ "Game Lobby"
    end

    test "includes all necessary UI sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby/ABC12345")
      # Success alert
      assert html =~ "alert-success"
      # Invite code display
      assert html =~ "code"
      # Player list
      assert html =~ "Players:"
      # How to play
      assert html =~ "collapse"
    end
  end
end
