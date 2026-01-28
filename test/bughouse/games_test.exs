defmodule Bughouse.GamesTest do
  use Bughouse.DataCase
  alias Bughouse.{Games, Accounts}

  describe "create_game/1" do
    test "creates game with unique invite code" do
      {:ok, game} = Games.create_game()

      assert game.invite_code
      assert String.length(game.invite_code) == 8
    end

    test "defaults to waiting status" do
      {:ok, game} = Games.create_game()
      assert game.status == :waiting
    end

    test "defaults to 10min time control" do
      {:ok, game} = Games.create_game()
      assert game.time_control == "10min"
    end

    test "all player positions are nil" do
      {:ok, game} = Games.create_game()

      assert is_nil(game.board_1_white_id)
      assert is_nil(game.board_1_black_id)
      assert is_nil(game.board_2_white_id)
      assert is_nil(game.board_2_black_id)
    end

    test "generates different codes for sequential games" do
      {:ok, game1} = Games.create_game()
      {:ok, game2} = Games.create_game()

      assert game1.invite_code != game2.invite_code
    end
  end

  describe "join_game/3" do
    setup do
      {:ok, game} = Games.create_game()
      {:ok, player} = Accounts.create_guest_player()
      %{game: game, player: player}
    end

    test "successfully joins player to board_1_white", %{game: game, player: player} do
      {:ok, updated_game} = Games.join_game(game.id, player.id, :board_1_white)

      assert updated_game.board_1_white_id == player.id
      assert updated_game.status == :waiting
    end

    test "successfully joins all 4 players to different positions", %{game: game} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      {:ok, game} = Games.join_game(game.id, p1.id, :board_1_white)
      {:ok, game} = Games.join_game(game.id, p2.id, :board_1_black)
      {:ok, game} = Games.join_game(game.id, p3.id, :board_2_white)
      {:ok, game} = Games.join_game(game.id, p4.id, :board_2_black)

      assert game.board_1_white_id == p1.id
      assert game.board_1_black_id == p2.id
      assert game.board_2_white_id == p3.id
      assert game.board_2_black_id == p4.id
    end

    test "game stays in waiting after all 4 players join", %{game: game} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      {:ok, game} = Games.join_game(game.id, p1.id, :board_1_white)
      {:ok, game} = Games.join_game(game.id, p2.id, :board_1_black)
      {:ok, game} = Games.join_game(game.id, p3.id, :board_2_white)
      {:ok, game} = Games.join_game(game.id, p4.id, :board_2_black)

      # Manual start required
      assert game.status == :waiting
    end

    test "returns error when position already taken", %{game: game, player: player} do
      {:ok, p2} = Accounts.create_guest_player()

      {:ok, _game} = Games.join_game(game.id, player.id, :board_1_white)
      assert {:error, :position_taken} = Games.join_game(game.id, p2.id, :board_1_white)
    end

    test "returns error when invalid position", %{game: game, player: player} do
      assert {:error, :invalid_position} = Games.join_game(game.id, player.id, :invalid)
    end

    test "returns error when player already in game", %{game: game, player: player} do
      {:ok, _game} = Games.join_game(game.id, player.id, :board_1_white)

      assert {:error, :player_already_joined} =
               Games.join_game(game.id, player.id, :board_1_black)
    end

    test "returns error when game not found", %{player: player} do
      fake_id = Ecto.UUID.generate()
      assert {:error, :game_not_found} = Games.join_game(fake_id, player.id, :board_1_white)
    end

    test "returns error when game already started", %{game: game, player: player} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      {:ok, game} = Games.join_game(game.id, p1.id, :board_1_white)
      {:ok, game} = Games.join_game(game.id, p2.id, :board_1_black)
      {:ok, game} = Games.join_game(game.id, p3.id, :board_2_white)
      {:ok, game} = Games.join_game(game.id, p4.id, :board_2_black)

      # Start the game
      {:ok, _game, _pid} = Games.start_game(game.id)

      # Try to join after game started
      assert {:error, :game_already_started} = Games.join_game(game.id, player.id, :board_1_white)
    end

    test "handles concurrent joins to same position (one succeeds)", %{game: game} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()

      # Simulate concurrent joins using Task
      task1 = Task.async(fn -> Games.join_game(game.id, p1.id, :board_1_white) end)
      task2 = Task.async(fn -> Games.join_game(game.id, p2.id, :board_1_white) end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)

      # One should succeed, one should fail
      results = [result1, result2]
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :position_taken}, &1)) == 1
    end
  end

  describe "join_game_random/2" do
    setup do
      {:ok, game} = Games.create_game()
      {:ok, player} = Accounts.create_guest_player()
      %{game: game, player: player}
    end

    test "assigns to board_1_white when game is empty", %{game: game, player: player} do
      {:ok, {updated_game, position}} = Games.join_game_random(game.id, player.id)

      assert position == :board_1_white
      assert updated_game.board_1_white_id == player.id
    end

    test "assigns to next available position", %{game: game} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()

      # Fill board_1_white
      {:ok, {_game, _pos}} = Games.join_game_random(game.id, p1.id)

      # Next player should get board_1_black
      {:ok, {updated_game, position}} = Games.join_game_random(game.id, p2.id)

      assert position == :board_1_black
      assert updated_game.board_1_black_id == p2.id
    end

    test "returns the assigned position", %{game: game, player: player} do
      {:ok, {_game, position}} = Games.join_game_random(game.id, player.id)

      assert position in [:board_1_white, :board_1_black, :board_2_white, :board_2_black]
    end

    test "returns error when game is full", %{game: game, player: player} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      # Fill all positions
      {:ok, _} = Games.join_game(game.id, p1.id, :board_1_white)
      {:ok, _} = Games.join_game(game.id, p2.id, :board_1_black)
      {:ok, _} = Games.join_game(game.id, p3.id, :board_2_white)
      {:ok, _} = Games.join_game(game.id, p4.id, :board_2_black)

      # Try to join full game
      assert {:error, :game_full} = Games.join_game_random(game.id, player.id)
    end

    test "returns error when game not found", %{player: player} do
      fake_id = Ecto.UUID.generate()
      assert {:error, :game_not_found} = Games.join_game_random(fake_id, player.id)
    end

    test "returns error when player already in game", %{game: game, player: player} do
      {:ok, {_game, _position}} = Games.join_game_random(game.id, player.id)
      assert {:error, :player_already_joined} = Games.join_game_random(game.id, player.id)
    end
  end

  describe "start_game/1" do
    setup do
      {:ok, game} = Games.create_game()
      %{game: game}
    end

    test "transitions game from waiting to in_progress when full", %{game: game} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      # Fill all positions
      {:ok, game} = Games.join_game(game.id, p1.id, :board_1_white)
      {:ok, game} = Games.join_game(game.id, p2.id, :board_1_black)
      {:ok, game} = Games.join_game(game.id, p3.id, :board_2_white)
      {:ok, game} = Games.join_game(game.id, p4.id, :board_2_black)

      assert game.status == :waiting

      # Start the game
      {:ok, started_game, pid} = Games.start_game(game.id)

      assert started_game.status == :in_progress

      # Clean up game server
      Bughouse.Games.BughouseGameServer.stop(pid)
    end

    test "returns error when game not full", %{game: game} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, _game} = Games.join_game(game.id, p1.id, :board_1_white)

      assert {:error, :not_enough_players} = Games.start_game(game.id)
    end

    test "returns error when game already started", %{game: game} do
      {:ok, p1} = Accounts.create_guest_player()
      {:ok, p2} = Accounts.create_guest_player()
      {:ok, p3} = Accounts.create_guest_player()
      {:ok, p4} = Accounts.create_guest_player()

      {:ok, game} = Games.join_game(game.id, p1.id, :board_1_white)
      {:ok, game} = Games.join_game(game.id, p2.id, :board_1_black)
      {:ok, game} = Games.join_game(game.id, p3.id, :board_2_white)
      {:ok, game} = Games.join_game(game.id, p4.id, :board_2_black)

      # Start the game
      {:ok, _started_game, pid} = Games.start_game(game.id)

      # Try to start again
      assert {:error, :game_already_started} = Games.start_game(game.id)

      # Clean up game server
      Bughouse.Games.BughouseGameServer.stop(pid)
    end

    test "returns error when game not found" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :game_not_found} = Games.start_game(fake_id)
    end
  end
end
