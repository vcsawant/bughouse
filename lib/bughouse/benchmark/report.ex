defmodule Bughouse.Benchmark.Report do
  @moduledoc """
  Builds and renders benchmark results: a JSON-ready map (string keys only),
  a human-readable text report, and atomic writes of the results file.

  Games with termination "aborted" (infrastructure failures) are listed but
  excluded from the win/draw/loss counts that feed the statistics.
  """

  alias Bughouse.Benchmark.{Spec, Stats}

  @doc """
  Builds the full report map from a match, its game rows (with :game preloaded),
  the run spec, and a status string (running | completed | cancelled | stopped_sprt).
  """
  def build(match, rows, %Spec{} = spec, status) do
    game_rows = Enum.map(rows, &game_row/1)
    scored = Enum.reject(game_rows, &(&1["termination"] == "aborted"))

    wins_a = Enum.count(scored, &(&1["winner"] == "a"))
    wins_b = Enum.count(scored, &(&1["winner"] == "b"))
    draws = Enum.count(scored, &(&1["winner"] == "draw"))
    aborted = length(game_rows) - length(scored)

    stats = Stats.summarize(wins_a, draws, wins_b, spec.sprt)

    %{
      "schema_version" => 1,
      "match_id" => match.id,
      "generated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "status" => status,
      "spec" => spec_map(spec),
      "score" => %{
        "games_played" => length(scored),
        "wins_a" => wins_a,
        "wins_b" => wins_b,
        "draws" => draws,
        "aborted" => aborted,
        "score_a" => Float.round(stats.score, 4),
        "score_a_pct" => Float.round(stats.score * 100, 2)
      },
      "stats" => stats_map(stats),
      "games" => game_rows
    }
  end

  @doc """
  Maps one BotMatchGame row (with :game preloaded) to a JSON-ready map.
  """
  def game_row(mg) do
    game = mg.game

    %{
      "game_number" => mg.game_number,
      "game_id" => mg.game_id,
      "invite_code" => game && game.invite_code,
      "result" => mg.result,
      "winner" => winner(mg.result),
      "termination" => termination(mg),
      "move_count" => game && length(game.moves || []),
      "bot_a_team" => mg.bot_a_team,
      "finished_at" => finished_at(game)
    }
  end

  @doc "Renders the report as human-readable text."
  def render_text(report) do
    spec = report["spec"]
    score = report["score"]
    stats = report["stats"]

    """
    ══════════════════════════════════════════════════════════════
     Benchmark: #{spec["name_a"]} vs #{spec["name_b"]}
     #{score["games_played"]}/#{spec["games"]} games · #{spec["time_control_ms"]}ms · status: #{report["status"]}
    ══════════════════════════════════════════════════════════════
     #{spec["name_a"]}: +#{score["wins_a"]} =#{score["draws"]} -#{score["wins_b"]}  (#{score["score_a_pct"]}%)#{aborted_line(score)}
     Elo: #{elo_line(stats)}
     #{stats["significance"]}#{sprt_line(stats)}#{termination_breakdown(report["games"])}
    ══════════════════════════════════════════════════════════════
    """
  end

  @doc "Encodes the report as pretty JSON and writes it atomically."
  def write_json!(report, path) do
    tmp_path = path <> ".tmp"
    File.write!(tmp_path, Jason.encode!(report, pretty: true))
    File.rename!(tmp_path, path)
    :ok
  end

  ## Internal

  defp winner("bot_a_win"), do: "a"
  defp winner("bot_b_win"), do: "b"
  defp winner(_), do: "draw"

  defp termination(mg) do
    mg.result_reason ||
      (mg.game && mg.game.result_details && mg.game.result_details["reason"]) ||
      "unknown"
  end

  defp finished_at(nil), do: nil
  defp finished_at(%{result_timestamp: nil}), do: nil

  defp finished_at(%{result_timestamp: ts}) do
    ts |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp spec_map(%Spec{} = spec) do
    %{
      "engine_a" => spec.engine_a,
      "engine_b" => spec.engine_b,
      "name_a" => spec.name_a,
      "name_b" => spec.name_b,
      "games" => spec.games,
      "time_control_ms" => spec.time_control_ms,
      "parallel" => spec.parallel,
      "options_a" => spec.options_a,
      "options_b" => spec.options_b,
      "sprt" => spec.sprt && Map.new(spec.sprt, fn {k, v} -> {Atom.to_string(k), v} end)
    }
  end

  defp stats_map(stats) do
    {significant, significance} = significance(stats)

    %{
      "elo_diff" => round1(stats.elo_diff),
      "elo_ci95" => ci_list(stats.elo_ci95),
      "los" => stats.los && Float.round(stats.los, 4),
      "significant" => significant,
      "significance" => significance,
      "sprt" => sprt_map(stats.sprt)
    }
  end

  defp significance(%{elo_ci95: nil}) do
    {false, "not statistically significant (not enough decisive games)"}
  end

  defp significance(%{elo_ci95: {low, high}}) do
    if low > 0.0 or high < 0.0 do
      {true, "statistically significant at 95% (CI excludes 0)"}
    else
      {false, "not statistically significant at 95% (CI includes 0; need more games)"}
    end
  end

  defp sprt_map(nil), do: nil

  defp sprt_map(sprt) do
    %{
      "llr" => Float.round(sprt.llr, 3),
      "lower" => Float.round(sprt.lower, 3),
      "upper" => Float.round(sprt.upper, 3),
      "decision" => Atom.to_string(sprt.decision)
    }
  end

  defp ci_list(nil), do: nil
  defp ci_list({low, high}), do: [round1(low), round1(high)]

  # `+ 0.0` normalizes -0.0 so JSON doesn't show "-0.0"
  defp round1(f) when is_float(f), do: Float.round(f, 1) + 0.0
  defp round1(other), do: other

  defp elo_line(%{"elo_diff" => elo, "elo_ci95" => nil}),
    do: "#{signed(elo)} (no confidence interval yet)"

  defp elo_line(%{"elo_diff" => elo, "elo_ci95" => [low, high], "los" => los}) do
    "#{signed(elo)} [#{signed(low)}, #{signed(high)}] (95% CI), LOS #{Float.round(los * 100, 1)}%"
  end

  # Fixed-decimal formatting (interpolation of large/negative-zero floats
  # produces "-2.4e3" / "-0.0")
  defp signed(f) when is_number(f) do
    f = f + 0.0
    if f >= 0, do: "+" <> fixed(f), else: fixed(f)
  end

  defp fixed(f), do: :erlang.float_to_binary(f, decimals: 1)

  defp aborted_line(%{"aborted" => 0}), do: ""
  defp aborted_line(%{"aborted" => n}), do: "  [#{n} aborted, excluded]"

  defp sprt_line(%{"sprt" => nil}), do: ""

  defp sprt_line(%{"sprt" => sprt}) do
    "\n SPRT: llr #{sprt["llr"]} [#{sprt["lower"]}, #{sprt["upper"]}] → #{sprt["decision"]}"
  end

  defp termination_breakdown([]), do: ""

  defp termination_breakdown(games) do
    breakdown =
      games
      |> Enum.frequencies_by(& &1["termination"])
      |> Enum.sort_by(fn {_reason, count} -> -count end)
      |> Enum.map_join(", ", fn {reason, count} -> "#{reason}: #{count}" end)

    "\n Terminations: #{breakdown}"
  end
end
