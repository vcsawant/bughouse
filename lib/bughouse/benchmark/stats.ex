defmodule Bughouse.Benchmark.Stats do
  @moduledoc """
  Match statistics for engine-vs-engine benchmarks.

  Uses the standard trinomial model over (win, draw, loss) counts for engine A
  (the same simple model cutechess-cli reports): score fraction → Elo difference
  via the logistic curve, normal-approximation confidence interval, likelihood
  of superiority, and a GSPRT log-likelihood ratio for early stopping.

  Caveat: the trinomial model treats games as independent, ignoring correlation
  within seat-alternated game pairs. A pentanomial model would be tighter; for
  this harness's purposes the simple model is sufficient (documented in
  bench/README.md).
  """

  @p_clamp 1.0e-6

  @doc "Score fraction for engine A: (wins + draws/2) / n."
  @spec score_fraction(non_neg_integer, non_neg_integer, non_neg_integer) :: float
  def score_fraction(w, d, l) do
    n = w + d + l
    if n == 0, do: 0.5, else: (w + d / 2) / n
  end

  @doc "Elo difference implied by a score fraction (clamped away from 0 and 1)."
  @spec elo_diff(float) :: float
  def elo_diff(p) do
    p = clamp(p)
    -400.0 * :math.log10(1.0 / p - 1.0)
  end

  @doc "Expected score fraction for a given Elo difference."
  @spec expected_score(float) :: float
  def expected_score(elo) do
    1.0 / (1.0 + :math.pow(10.0, -elo / 400.0))
  end

  @doc """
  ~95% (z=1.96) confidence interval on the Elo difference, from the normal
  approximation on the score fraction mapped through the Elo curve.
  Returns `{low, high}` or `nil` when there is no variance (n < 2 or all draws).
  """
  @spec elo_interval(non_neg_integer, non_neg_integer, non_neg_integer, float) ::
          {float, float} | nil
  def elo_interval(w, d, l, z \\ 1.96) do
    n = w + d + l

    with true <- n >= 2,
         se when is_float(se) and se > 0.0 <- standard_error(w, d, l) do
      p = score_fraction(w, d, l)
      {elo_diff(p - z * se), elo_diff(p + z * se)}
    else
      _ -> nil
    end
  end

  @doc """
  Likelihood of superiority: probability that engine A is genuinely stronger,
  under the normal approximation. Returns `nil` when there is no variance.
  """
  @spec los(non_neg_integer, non_neg_integer, non_neg_integer) :: float | nil
  def los(w, d, l) do
    case standard_error(w, d, l) do
      se when is_float(se) and se > 0.0 ->
        p = score_fraction(w, d, l)
        0.5 * (1.0 + :math.erf((p - 0.5) / (se * :math.sqrt(2.0))))

      _ ->
        nil
    end
  end

  @doc """
  GSPRT approximation of the sequential probability ratio test between
  H0 (elo diff = elo0) and H1 (elo diff = elo1).

  Returns `%{llr, lower, upper, decision}` where decision is
  `:accept_h1` (A is at least elo1 stronger), `:accept_h0`, or `:continue`.
  """
  @spec sprt(non_neg_integer, non_neg_integer, non_neg_integer, map()) :: map()
  def sprt(w, d, l, %{elo0: elo0, elo1: elo1, alpha: alpha, beta: beta}) do
    n = w + d + l
    lower = :math.log(beta / (1.0 - alpha))
    upper = :math.log((1.0 - beta) / alpha)

    variance = variance(w, d, l)

    llr =
      if n == 0 or variance <= 0.0 do
        0.0
      else
        p = score_fraction(w, d, l)
        s0 = expected_score(elo0)
        s1 = expected_score(elo1)
        (s1 - s0) * (2.0 * p - s0 - s1) / (2.0 * variance / n)
      end

    decision =
      cond do
        llr >= upper -> :accept_h1
        llr <= lower -> :accept_h0
        true -> :continue
      end

    %{llr: llr, lower: lower, upper: upper, decision: decision}
  end

  @doc """
  Bundles score, Elo, CI, LOS, and (optionally) SPRT into one map for reporting.
  """
  @spec summarize(non_neg_integer, non_neg_integer, non_neg_integer, map() | nil) :: map()
  def summarize(w, d, l, sprt_params \\ nil) do
    %{
      n: w + d + l,
      wins: w,
      draws: d,
      losses: l,
      score: score_fraction(w, d, l),
      elo_diff: elo_diff(score_fraction(w, d, l)),
      elo_ci95: elo_interval(w, d, l),
      los: los(w, d, l),
      sprt: if(sprt_params, do: sprt(w, d, l, sprt_params))
    }
  end

  ## Internal

  # Per-game score variance of the trinomial (win=1, draw=0.5, loss=0) sample.
  defp variance(w, d, l) do
    n = w + d + l

    if n == 0 do
      0.0
    else
      p = score_fraction(w, d, l)
      (w * :math.pow(1.0 - p, 2) + d * :math.pow(0.5 - p, 2) + l * :math.pow(p, 2)) / n
    end
  end

  defp standard_error(w, d, l) do
    n = w + d + l

    case variance(w, d, l) do
      var when var > 0.0 and n > 0 -> :math.sqrt(var / n)
      _ -> nil
    end
  end

  defp clamp(p), do: p |> max(@p_clamp) |> min(1.0 - @p_clamp)
end
