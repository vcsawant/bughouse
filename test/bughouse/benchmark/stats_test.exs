defmodule Bughouse.Benchmark.StatsTest do
  use ExUnit.Case, async: true

  alias Bughouse.Benchmark.Stats

  @sprt_params %{elo0: 0.0, elo1: 10.0, alpha: 0.05, beta: 0.05}

  describe "score_fraction/3" do
    test "wins count 1, draws count half" do
      assert Stats.score_fraction(5, 2, 3) == 0.6
    end

    test "no games is an even score" do
      assert Stats.score_fraction(0, 0, 0) == 0.5
    end

    test "all wins" do
      assert Stats.score_fraction(10, 0, 0) == 1.0
    end
  end

  describe "elo_diff/1" do
    test "even score is zero Elo" do
      assert Stats.elo_diff(0.5) == 0.0
    end

    test "75% score is about +191 Elo" do
      assert_in_delta Stats.elo_diff(0.75), 190.85, 0.01
    end

    test "25% score is the mirror image" do
      assert_in_delta Stats.elo_diff(0.25), -Stats.elo_diff(0.75), 1.0e-9
    end

    test "clamps extreme scores to finite values" do
      assert is_float(Stats.elo_diff(1.0))
      assert is_float(Stats.elo_diff(0.0))
      assert Stats.elo_diff(1.0) > 0
      assert Stats.elo_diff(0.0) < 0
    end
  end

  describe "expected_score/1" do
    test "zero Elo is an even score" do
      assert Stats.expected_score(0.0) == 0.5
    end

    test "round-trips with elo_diff" do
      assert_in_delta Stats.expected_score(Stats.elo_diff(0.65)), 0.65, 1.0e-9
    end
  end

  describe "elo_interval/4" do
    test "is ordered and contains the point estimate" do
      {low, high} = Stats.elo_interval(60, 20, 20)
      point = Stats.elo_diff(Stats.score_fraction(60, 20, 20))

      assert low < high
      assert low < point and point < high
    end

    test "narrows with more games at the same score" do
      {low_small, high_small} = Stats.elo_interval(6, 2, 2)
      {low_big, high_big} = Stats.elo_interval(600, 200, 200)

      assert high_big - low_big < high_small - low_small
    end

    test "nil when all games are draws (no variance)" do
      assert Stats.elo_interval(0, 50, 0) == nil
    end

    test "nil with fewer than 2 games" do
      assert Stats.elo_interval(1, 0, 0) == nil
    end
  end

  describe "los/3" do
    test "even results give 50%" do
      assert_in_delta Stats.los(50, 0, 50), 0.5, 1.0e-9
    end

    test "dominant A gives high LOS" do
      assert Stats.los(70, 0, 30) > 0.95
    end

    test "dominant B gives low LOS" do
      assert Stats.los(30, 0, 70) < 0.05
    end

    test "nil when no variance" do
      assert Stats.los(0, 10, 0) == nil
    end
  end

  describe "sprt/4" do
    test "bounds at alpha=beta=0.05" do
      %{lower: lower, upper: upper} = Stats.sprt(10, 0, 10, @sprt_params)
      assert_in_delta lower, -2.944, 0.001
      assert_in_delta upper, 2.944, 0.001
    end

    test "llr is zero with no variance" do
      assert %{llr: 0.0, decision: :continue} = Stats.sprt(0, 0, 0, @sprt_params)
      assert %{llr: 0.0, decision: :continue} = Stats.sprt(0, 20, 0, @sprt_params)
    end

    test "strong A accepts H1" do
      assert %{decision: :accept_h1} = Stats.sprt(300, 100, 100, @sprt_params)
    end

    test "strong B accepts H0" do
      assert %{decision: :accept_h0} = Stats.sprt(100, 100, 300, @sprt_params)
    end

    test "llr grows with more A wins" do
      llrs =
        for w <- [55, 60, 65] do
          Stats.sprt(w, 0, 50, @sprt_params).llr
        end

      assert llrs == Enum.sort(llrs)
    end
  end

  describe "summarize/4" do
    test "bundles all statistics" do
      summary = Stats.summarize(12, 4, 8, @sprt_params)

      assert summary.n == 24
      assert summary.score == Stats.score_fraction(12, 4, 8)
      assert {_, _} = summary.elo_ci95
      assert is_float(summary.los)
      assert summary.sprt.decision in [:continue, :accept_h0, :accept_h1]
    end

    test "sprt is nil when no params given" do
      assert Stats.summarize(5, 0, 5).sprt == nil
    end
  end
end
