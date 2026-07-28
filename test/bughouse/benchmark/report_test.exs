defmodule Bughouse.Benchmark.ReportTest do
  use ExUnit.Case, async: true

  alias Bughouse.Benchmark.{Report, Spec}
  alias Bughouse.Schemas.Games.{BotMatch, BotMatchGame, Game}

  @spec_fixture %Spec{
    engine_a: "/x/a",
    engine_b: "/x/b",
    name_a: "a",
    name_b: "b",
    games: 10,
    time_control_ms: 60_000
  }

  defp row(result, bot_a_team, opts \\ []) do
    %BotMatchGame{
      game_number: Keyword.get(opts, :number, 1),
      game_id: "gid",
      result: result,
      result_reason: Keyword.get(opts, :reason),
      bot_a_team: bot_a_team,
      game: %Game{
        invite_code: "ABCD1234",
        moves: Keyword.get(opts, :moves, []),
        result_details: Keyword.get(opts, :result_details),
        result_timestamp: nil
      }
    }
  end

  describe "game_row/1" do
    test "winner mapping covers all results independent of seating" do
      for team <- ["team_1", "team_2"] do
        assert Report.game_row(row("bot_a_win", team))["winner"] == "a"
        assert Report.game_row(row("bot_b_win", team))["winner"] == "b"
        assert Report.game_row(row("draw", team))["winner"] == "draw"
      end
    end

    test "termination prefers result_reason over game result_details" do
      r =
        row("bot_a_win", "team_1",
          reason: "forfeit_crash",
          result_details: %{"reason" => "timeout"}
        )

      assert Report.game_row(r)["termination"] == "forfeit_crash"
    end

    test "termination falls back to game result_details, then unknown" do
      r = row("bot_a_win", "team_1", result_details: %{"reason" => "checkmate"})
      assert Report.game_row(r)["termination"] == "checkmate"

      assert Report.game_row(row("draw", "team_1"))["termination"] == "unknown"
    end

    test "move_count comes from the game's move list" do
      r = row("bot_a_win", "team_1", moves: [%{}, %{}, %{}])
      assert Report.game_row(r)["move_count"] == 3
    end
  end

  describe "build/4" do
    test "aborted games are listed but excluded from statistics" do
      match = %BotMatch{id: "match-1"}

      rows = [
        row("bot_a_win", "team_1", reason: "checkmate"),
        row("draw", "team_2", reason: "aborted"),
        row("bot_b_win", "team_1", reason: "timeout")
      ]

      report = Report.build(match, rows, @spec_fixture, "running")

      assert report["score"]["games_played"] == 2
      assert report["score"]["wins_a"] == 1
      assert report["score"]["wins_b"] == 1
      assert report["score"]["draws"] == 0
      assert report["score"]["aborted"] == 1
      assert length(report["games"]) == 3
    end

    test "output is JSON-encodable" do
      match = %BotMatch{id: "match-1"}
      rows = [row("bot_a_win", "team_1", reason: "checkmate")]

      spec = %{@spec_fixture | sprt: %{elo0: 0.0, elo1: 10.0, alpha: 0.05, beta: 0.05}}
      report = Report.build(match, rows, spec, "completed")

      assert {:ok, encoded} = Jason.encode(report)
      assert {:ok, decoded} = Jason.decode(encoded)
      assert decoded["match_id"] == "match-1"
      assert decoded["spec"]["sprt"]["elo1"] == 10.0
    end

    test "render_text mentions names, score, and significance" do
      match = %BotMatch{id: "match-1"}

      rows =
        for n <- 1..10 do
          row("bot_a_win", "team_1", reason: "checkmate", number: n)
        end

      text =
        match
        |> Report.build(rows, @spec_fixture, "completed")
        |> Report.render_text()

      assert text =~ "a vs b"
      assert text =~ "+10 =0 -0"
      assert text =~ "checkmate: 10"
    end
  end

  describe "write_json!/2" do
    test "writes atomically, leaving no tmp file" do
      dir = System.tmp_dir!()
      path = Path.join(dir, "bench_report_test_#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)

      report = Report.build(%BotMatch{id: "m"}, [], @spec_fixture, "running")
      assert :ok = Report.write_json!(report, path)

      assert File.exists?(path)
      refute File.exists?(path <> ".tmp")
      assert {:ok, _} = Jason.decode(File.read!(path))
    end
  end
end
