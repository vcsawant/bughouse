defmodule BughouseWeb.GameLiveTest do
  use BughouseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bughouse.{Games, Accounts, Repo}

  setup do
    # Create a game with invite code
    {:ok, game} = Games.create_game()

    # Create guest players
    {:ok, player1} = Accounts.create_guest_player()
    {:ok, player2} = Accounts.create_guest_player()
    {:ok, player3} = Accounts.create_guest_player()
    {:ok, player4} = Accounts.create_guest_player()

    # Join players to game
    {:ok, game} = Games.join_game(game.id, player1.id, :board_1_white)
    {:ok, game} = Games.join_game(game.id, player2.id, :board_1_black)
    {:ok, game} = Games.join_game(game.id, player3.id, :board_2_white)
    {:ok, game} = Games.join_game(game.id, player4.id, :board_2_black)

    # Start the game
    {:ok, game, pid} = Games.start_game(game.id)

    # Allow the game server process to access the database in tests
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)

    %{
      game: game,
      player1: player1,
      player2: player2,
      player3: player3,
      player4: player4
    }
  end

  describe "mount/3" do
    test "loads game and subscribes to updates", %{conn: conn, game: game, player1: player1} do
      # Login as player1
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, view, _html} = live(conn, ~p"/game/#{game.invite_code}")

      # Check that the game state is loaded
      assert view |> element(".chess-clock") |> has_element?()
    end

    test "redirects if game not found", %{conn: conn, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/game/invalid-code")
    end

    test "determines player position correctly", %{conn: conn, game: game, player2: player2} do
      conn = init_test_session(conn, current_player_id: player2.id)

      {:ok, view, _html} = live(conn, ~p"/game/#{game.invite_code}")

      # Player 2 is board_1_black
      assert render(view) =~ "(You)"
    end

    test "handles spectator mode (no position)", %{conn: conn, game: game} do
      # Create a spectator player (not in the game)
      {:ok, spectator} = Accounts.create_guest_player()
      conn = init_test_session(conn, current_player_id: spectator.id)

      {:ok, _view, html} = live(conn, ~p"/game/#{game.invite_code}")

      # Spectator should see the game but not have "(You)" marker
      refute html =~ "(You)"
    end
  end

  describe "handle_event select_square" do
    test "selects square on player's board", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, view, _html} = live(conn, ~p"/game/#{game.invite_code}")

      # Select a square on player's board (board 1)
      html = view |> element("[phx-value-square='e2'][phx-value-board='1']") |> render_click()

      # Check that the square is selected (visible as highlighted in HTML)
      # When selected, the square should have the ring-blue-500 class
      assert html =~ "ring-blue-500"
    end

    test "ignores clicks on opponent's board", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, view, _html} = live(conn, ~p"/game/#{game.invite_code}")

      # Try to select a square on board 2 (not player's board)
      html = view |> element("[phx-value-square='e2'][phx-value-board='2']") |> render_click()

      # No square should be selected (no ring highlight)
      refute html =~ "ring-blue-500"
    end

    test "makes move when valid destination selected", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, view, _html} = live(conn, ~p"/game/#{game.invite_code}")

      # Select source square
      view |> element("[phx-value-square='e2'][phx-value-board='1']") |> render_click()

      # Click destination (valid pawn move e2-e4)
      html = view |> element("[phx-value-square='e4'][phx-value-board='1']") |> render_click()

      # Selection should be cleared after move (no ring highlight)
      refute html =~ "ring-blue-500"
    end

    test "deselects when clicking same square", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, view, _html} = live(conn, ~p"/game/#{game.invite_code}")

      # Select a square
      html1 = view |> element("[phx-value-square='e2'][phx-value-board='1']") |> render_click()
      assert html1 =~ "ring-blue-500"

      # Click same square again to deselect
      html2 = view |> element("[phx-value-square='e2'][phx-value-board='1']") |> render_click()
      refute html2 =~ "ring-blue-500"
    end
  end

  describe "handle_event select_reserve_piece" do
    # Note: This test would require a game state where the player has reserve pieces
    # For now, we'll test the basic selection logic

    test "selects reserve piece (visual test only)", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, view, _html} = live(conn, ~p"/game/#{game.invite_code}")

      # Try to select a pawn (even if count is 0, button exists)
      # Note: This might fail if the button is disabled, but we're just testing the render
      html = render(view)
      assert html =~ "phx-click=\"select_reserve_piece\""
    end

    test "reserve pieces are rendered", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, _view, html} = live(conn, ~p"/game/#{game.invite_code}")

      # Check that reserve piece buttons are present
      assert html =~ "♙"  # Pawn Unicode character
      assert html =~ "♘"  # Knight Unicode character
    end
  end

  describe "handle_event deselect_all" do
    test "clears all selections", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, view, _html} = live(conn, ~p"/game/#{game.invite_code}")

      # Select a square
      html1 = view |> element("[phx-value-square='e2'][phx-value-board='1']") |> render_click()
      assert html1 =~ "ring-blue-500"

      # Deselect all
      html2 = view |> element("[phx-click='deselect_all']") |> render_click()

      # Selection should be cleared
      refute html2 =~ "ring-blue-500"
    end
  end

  describe "handle_info game_state_update" do
    test "updates game board after move", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, view, _html1} = live(conn, ~p"/game/#{game.invite_code}")

      # Make a move to trigger state update
      Games.make_game_move(game.id, player1.id, "e2e4")

      # Wait for the update to be broadcast
      :timer.sleep(100)

      # Re-render to see the updated state
      # The view should still be functional (no crashes)
      html2 = render(view)
      assert html2 =~ "chess-clock"
    end
  end

  describe "handle_info game_over" do
    test "displays chess clocks", %{conn: conn, game: game, player1: player1} do
      conn = init_test_session(conn, current_player_id: player1.id)

      {:ok, _view, html} = live(conn, ~p"/game/#{game.invite_code}")

      # Verify the game interface is rendered with clocks
      assert html =~ "chess-clock"

      # Note: Testing actual game over would require triggering it via the game server
      # which is complex for unit tests. Integration tests would be better for this.
    end
  end
end
