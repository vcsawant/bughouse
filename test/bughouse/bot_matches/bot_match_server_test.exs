defmodule Bughouse.BotMatches.BotMatchServerTest do
  use ExUnit.Case, async: true

  alias Bughouse.BotMatches.BotMatchServer

  describe "bot_a_team_for_game/1" do
    test "alternates by game parity, starting with team_1" do
      assert BotMatchServer.bot_a_team_for_game(1) == :team_1
      assert BotMatchServer.bot_a_team_for_game(2) == :team_2
      assert BotMatchServer.bot_a_team_for_game(3) == :team_1
      assert BotMatchServer.bot_a_team_for_game(4) == :team_2
      assert BotMatchServer.bot_a_team_for_game(99) == :team_1
      assert BotMatchServer.bot_a_team_for_game(100) == :team_2
    end
  end

  describe "map_game_result/2" do
    test "maps winning team relative to bot_a's seat" do
      assert BotMatchServer.map_game_result(:team_1, :team_1) == "bot_a_win"
      assert BotMatchServer.map_game_result(:team_2, :team_1) == "bot_b_win"
      assert BotMatchServer.map_game_result(:team_1, :team_2) == "bot_b_win"
      assert BotMatchServer.map_game_result(:team_2, :team_2) == "bot_a_win"
    end

    test "draws and unknown results map to draw" do
      assert BotMatchServer.map_game_result(:draw, :team_1) == "draw"
      assert BotMatchServer.map_game_result(:draw, :team_2) == "draw"
      assert BotMatchServer.map_game_result(nil, :team_1) == "draw"
    end
  end
end
