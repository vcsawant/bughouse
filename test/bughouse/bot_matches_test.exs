defmodule Bughouse.BotMatchesTest do
  use Bughouse.DataCase, async: false

  alias Bughouse.{BotMatches, Games, Repo}
  alias Bughouse.Schemas.Accounts.{Bot, Player}

  defp create_bot!(name) do
    player =
      %Player{}
      |> Player.changeset(%{
        username: name,
        display_name: name,
        is_bot: true,
        guest: false,
        current_rating: 1200,
        peak_rating: 1200,
        total_games: 0,
        wins: 0,
        losses: 0,
        draws: 0
      })
      |> Repo.insert!()

    %Bot{}
    |> Bot.changeset(%{
      player_id: player.id,
      owner_id: player.id,
      name: name,
      display_name: name,
      bot_type: "internal",
      is_public: false,
      is_active: true
    })
    |> Repo.insert!()
  end

  defp create_match! do
    bot_a = create_bot!("test_bench_a")
    bot_b = create_bot!("test_bench_b")

    {:ok, match} =
      BotMatches.create_match(%{
        bot_a_id: bot_a.id,
        bot_b_id: bot_b.id,
        total_games: 4,
        time_control_ms: 60_000,
        created_by_id: bot_a.player_id
      })

    match
  end

  describe "record_game_result/6" do
    test "persists result_reason and increments the right counter" do
      match = create_match!()
      {:ok, game} = Games.create_game(%{time_control: "1min"})

      {:ok, match} =
        BotMatches.record_game_result(match, game.id, 1, "bot_a_win", "team_1", "forfeit_crash")

      assert match.bot_a_wins == 1
      assert match.completed_games == 1

      [row] = BotMatches.list_match_game_rows(match.id)
      assert row.result == "bot_a_win"
      assert row.result_reason == "forfeit_crash"
      assert row.bot_a_team == "team_1"
    end

    test "accepts a nil reason (back-compat)" do
      match = create_match!()
      {:ok, game} = Games.create_game(%{time_control: "1min"})

      {:ok, match} = BotMatches.record_game_result(match, game.id, 1, "draw", "team_2")

      assert match.draws == 1
      [row] = BotMatches.list_match_game_rows(match.id)
      assert row.result_reason == nil
    end

    test "rejects an invalid reason" do
      match = create_match!()
      {:ok, game} = Games.create_game(%{time_control: "1min"})

      assert {:error, changeset} =
               BotMatches.record_game_result(match, game.id, 1, "draw", "team_1", "rage_quit")

      assert %{result_reason: _} = errors_on(changeset)
    end
  end

  describe "list_match_game_rows/1" do
    test "returns rows ordered by game number with games preloaded" do
      match = create_match!()
      {:ok, g1} = Games.create_game(%{time_control: "1min"})
      {:ok, g2} = Games.create_game(%{time_control: "1min"})

      {:ok, match} =
        BotMatches.record_game_result(match, g2.id, 2, "bot_b_win", "team_2", "timeout")

      {:ok, _match} =
        BotMatches.record_game_result(match, g1.id, 1, "bot_a_win", "team_1", "checkmate")

      rows = BotMatches.list_match_game_rows(match.id)

      assert Enum.map(rows, & &1.game_number) == [1, 2]
      assert Enum.all?(rows, &match?(%{invite_code: code} when is_binary(code), &1.game))
    end
  end

  describe "time_control_ms_to_string/1" do
    test "known presets keep their labels" do
      assert BotMatches.time_control_ms_to_string(60_000) == "1min"
      assert BotMatches.time_control_ms_to_string(300_000) == "5min"
    end

    test "arbitrary values use the ms format the game server can parse" do
      assert BotMatches.time_control_ms_to_string(90_000) == "90000ms"
      assert BotMatches.time_control_ms_to_string(5_000) == "5000ms"
    end
  end
end
