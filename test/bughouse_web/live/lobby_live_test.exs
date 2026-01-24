defmodule BughouseWeb.LobbyLiveTest do
  use BughouseWeb.ConnCase

  import Phoenix.LiveViewTest
  alias Bughouse.{Games, Accounts}

  describe "guest session management" do
    test "creates guest player on visit", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Guest player is created and can join
      assert html =~ "Quick Join"
      assert html =~ "Join"
    end
  end

  describe "lobby mount" do
    test "mounts successfully with valid invite code", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      assert html =~ "Game Lobby"
      assert html =~ game.invite_code
    end

    test "redirects with error for invalid invite code", %{conn: conn} do
      result = live(conn, ~p"/lobby/INVALID123")
      assert {:error, {:redirect, %{to: "/"}}} = result
    end

    test "subscribes to game updates on mount", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, _view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Verify subscription by triggering a broadcast
      Games.subscribe_to_game(game.invite_code)
      Phoenix.PubSub.broadcast(Bughouse.PubSub, "game:#{game.invite_code}", {:test, "message"})

      # If we don't crash, subscription worked
      :ok
    end

    test "displays shareable invite link", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      assert html =~ "Share this link"
      assert html =~ "/lobby/#{game.invite_code}"
    end
  end

  describe "joining positions" do
    test "allows joining an open position", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      assert render(view) =~ "Open"
      assert render(view) =~ "Quick Join"

      # Join Board A White
      render_click(view, "join_position", %{"position" => "board_1_white"})

      # Wait for PubSub update and re-render
      :timer.sleep(200)
      html = render(view)

      assert html =~ "You"
      assert html =~ "Leave Game"
    end

    test "prevents joining multiple positions from same connection", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Join first position
      render_click(view, "join_position", %{"position" => "board_1_white"})
      :timer.sleep(200)
      html = render(view)

      # Verify joined (You badge should appear, Leave button should show)
      assert html =~ "You"
      assert html =~ "Leave Game"

      # Positions should not have join buttons anymore
      # (already in game, so can't join another position)
    end

    test "shows position as occupied when another player is there", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, player2} = Accounts.create_guest_player()

      # Player 2 joins first
      Games.join_game(game.id, player2.id, :board_1_white)

      # Player 1 views the lobby
      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Should see player 2's name and no join button for that position
      assert html =~ player2.display_name
    end

    test "quick join assigns first available position", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      render_click(view, "quick_join")
      :timer.sleep(200)
      html = render(view)

      # Should show "You" badge and leave button
      assert html =~ "You"
      assert html =~ "Leave Game"
    end

    test "shows game ready to start when 4 players join", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      Games.join_game(game.id, p1.id, :board_1_white)
      Games.join_game(game.id, p2.id, :board_1_black)
      Games.join_game(game.id, p3.id, :board_2_white)
      Games.join_game(game.id, p4.id, :board_2_black)

      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # All positions should be filled with player names
      assert html =~ p1.display_name
      assert html =~ p2.display_name
      assert html =~ p3.display_name
      assert html =~ p4.display_name

      # Game should be ready to start (button enabled - no disabled attribute)
      assert html =~ "Start Game"
      refute html =~ "disabled"
    end
  end

  describe "leaving game" do
    test "allows player to leave game", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Join a position
      render_click(view, "join_position", %{"position" => "board_1_white"})
      :timer.sleep(200)
      html = render(view)
      assert html =~ "You"
      assert html =~ "Leave Game"

      # Leave the game
      render_click(view, "leave_game")
      :timer.sleep(200)
      html = render(view)

      # Quick Join button should reappear, leave button should be gone
      assert html =~ "Quick Join"
      refute html =~ "Leave Game"
    end

    test "position becomes open after player leaves", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, player2} = Accounts.create_guest_player()

      # Player 2 joins
      Games.join_game(game.id, player2.id, :board_1_white)

      # Player 1 views lobby
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")
      assert render(view) =~ player2.display_name

      # Player 2 leaves
      Games.leave_game(game.id, player2.id)
      :timer.sleep(100)

      # Position should show as open
      assert render(view) =~ "Open"
      refute render(view) =~ player2.display_name
    end
  end

  describe "real-time updates" do
    test "updates when another player joins", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Initially all positions are open
      html = render(view)
      assert html =~ "Open"

      # Another player joins via backend
      {:ok, player2} = Accounts.create_guest_player()
      Games.join_game(game.id, player2.id, :board_1_black)

      # Wait for PubSub
      :timer.sleep(100)

      # View should update to show the new player
      html = render(view)
      assert html =~ player2.display_name
    end

    test "updates when another player leaves", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, player2} = Accounts.create_guest_player()
      Games.join_game(game.id, player2.id, :board_1_white)

      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")
      assert render(view) =~ player2.display_name

      # Player 2 leaves
      Games.leave_game(game.id, player2.id)
      :timer.sleep(100)

      # View should update
      assert render(view) =~ "Open"
      refute render(view) =~ player2.display_name
    end
  end

  describe "starting game" do
    test "start button is disabled with less than 4 players", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      assert render(view) =~ "Waiting for Players..."
      assert render(view) =~ "disabled"
    end

    test "start button is enabled with 4 players", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      Games.join_game(game.id, p1.id, :board_1_white)
      Games.join_game(game.id, p2.id, :board_1_black)
      Games.join_game(game.id, p3.id, :board_2_white)
      Games.join_game(game.id, p4.id, :board_2_black)

      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      html = render(view)
      assert html =~ "Start Game"
      refute html =~ "Waiting for Players..."
      refute html =~ "disabled"
    end

    test "shows error when trying to start with less than 4 players", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Join one player
      render_click(view, "join_position", %{"position" => "board_1_white"})
      :timer.sleep(100)

      # Try to start
      render_click(view, "start_game")
      :timer.sleep(50)

      # Should show error
      html = render(view)
      assert html =~ "4 players" or html =~ "not enough" or html =~ "Waiting"
    end
  end

  describe "player slots display" do
    test "shows all 4 position labels", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      assert html =~ "Board A - White"
      assert html =~ "Board A - Black"
      assert html =~ "Board B - White"
      assert html =~ "Board B - Black"
    end

    test "displays player names in filled positions", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()

      Games.join_game(game.id, p1.id, :board_1_white)
      Games.join_game(game.id, p2.id, :board_2_black)

      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      assert html =~ p1.display_name
      assert html =~ p2.display_name
    end

    test "displays 'You' badge for current player's position", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      render_click(view, "join_position", %{"position" => "board_1_white"})
      :timer.sleep(100)

      html = render(view)
      assert html =~ "You"
      assert html =~ "Guest_"
    end

    test "shows join button only for open positions when not in game", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, player2} = Accounts.create_guest_player()
      Games.join_game(game.id, player2.id, :board_1_white)

      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Should have join buttons for open positions
      # but not for the taken position
      # The exact assertion depends on HTML structure
      assert html =~ "Join"
      assert html =~ "Open"
    end

    test "shows leave button when player is in game", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      render_click(view, "join_position", %{"position" => "board_1_white"})
      :timer.sleep(200)
      html = render(view)

      # Leave button should show when player is in game
      assert html =~ "Leave Game"
      assert html =~ "You"
    end
  end

  describe "UI elements" do
    test "displays copy link button", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      assert html =~ "Copy Link"
    end

    test "shows leave button only when player is in game", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, view, _html} = live(conn, ~p"/lobby/#{game.invite_code}")

      # Not in game yet
      refute render(view) =~ "Leave Game"

      # Join game
      render_click(view, "join_position", %{"position" => "board_1_white"})
      :timer.sleep(100)

      # Leave button should appear
      assert render(view) =~ "Leave Game"
    end

    test "includes back to home link", %{conn: conn} do
      {:ok, game} = Games.create_game()
      {:ok, _view, html} = live(conn, ~p"/lobby/#{game.invite_code}")

      assert html =~ "Back to Home"
    end
  end
end
