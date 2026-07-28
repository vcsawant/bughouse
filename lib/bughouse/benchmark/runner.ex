defmodule Bughouse.Benchmark.Runner do
  @moduledoc """
  Orchestrates a benchmark run on top of the existing bot-match infrastructure:
  upserts two persistent bench Bot records, creates and starts a BotMatch, then
  follows the match over PubSub, rewriting the results JSON after every game
  and applying SPRT early stopping when configured.
  """

  require Logger

  alias Bughouse.{BotMatches, Bots, Repo}
  alias Bughouse.Benchmark.{Report, Spec}
  alias Bughouse.BotMatches.BotMatchServer
  alias Bughouse.Schemas.Accounts.{Bot, Player}

  # Fixed DB names for the two bench identities (Bot.name must match
  # ^[a-zA-Z0-9_]{3,20}$ and be unique); human-facing labels live in
  # display_name and the report.
  @bench_bot_a "bench_a"
  @bench_bot_b "bench_b"

  @doc """
  Runs a benchmark to completion. Returns `{:ok, report}` (the final report map,
  also written to `<output_dir>/<match_id>/results.json`) or `{:error, reason}`.
  """
  @spec run(Spec.t()) :: {:ok, map()} | {:error, term()}
  def run(%Spec{} = spec) do
    with {:ok, bot_a} <-
           upsert_bench_bot(@bench_bot_a, spec.name_a, spec.engine_a, spec.options_a),
         {:ok, bot_b} <-
           upsert_bench_bot(@bench_bot_b, spec.name_b, spec.engine_b, spec.options_b),
         {:ok, match} <- create_match(spec, bot_a, bot_b) do
      out_dir = Path.join(spec.output_dir, match.id)
      File.mkdir_p!(out_dir)
      out_path = Path.join(out_dir, "results.json")

      Report.build(match, [], spec, "running") |> Report.write_json!(out_path)

      BotMatches.subscribe_to_match(match.id)

      case BotMatches.start_match(match) do
        {:ok, _match} ->
          Logger.info("Benchmark match #{match.id} started → #{out_path}")
          await_match(match.id, spec, out_path, "running")

        {:error, reason} ->
          {:error, {:start_match_failed, reason}}
      end
    end
  end

  @doc """
  Creates or updates a persistent bench bot (self-owned, non-public), pointing
  it at the given engine binary with the given UBI options.
  """
  def upsert_bench_bot(name, display_name, engine_path, options) do
    engine_path = Path.expand(engine_path)

    case Bots.get_bot_by_name(name) do
      nil -> create_bench_bot(name, display_name, engine_path, options)
      bot -> update_bench_bot(bot, display_name, engine_path, options)
    end
  end

  ## Internal — bots

  defp create_bench_bot(name, display_name, engine_path, options) do
    # Same self-owned pattern as priv/repo/seeds.exs: the bot's game identity
    # Player doubles as its owner.
    player =
      case Repo.get_by(Player, username: name) do
        nil ->
          %Player{}
          |> Player.changeset(%{
            username: name,
            display_name: display_name,
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

        existing ->
          existing
      end

    %Bot{}
    |> Bot.changeset(%{
      player_id: player.id,
      owner_id: player.id,
      name: name,
      display_name: display_name,
      description: "Benchmark harness engine (mix benchmark)",
      bot_type: "internal",
      status: "online",
      is_public: false,
      is_active: true,
      engine_path: engine_path,
      config: %{},
      default_options: options
    })
    |> Repo.insert()
  end

  defp update_bench_bot(bot, display_name, engine_path, options) do
    Bots.update_bot(bot, %{
      display_name: display_name,
      engine_path: engine_path,
      default_options: options,
      is_active: true,
      status: "online"
    })
  end

  defp create_match(spec, bot_a, bot_b) do
    BotMatches.create_match(%{
      bot_a_id: bot_a.id,
      bot_b_id: bot_b.id,
      total_games: spec.games,
      time_control_ms: spec.time_control_ms,
      parallel_games: spec.parallel,
      created_by_id: bot_a.player_id
    })
  end

  ## Internal — match following

  defp await_match(match_id, spec, out_path, status) do
    timeout = max(5 * spec.time_control_ms, 120_000)

    receive do
      {:match_update, %{id: ^match_id} = match} ->
        rows = BotMatches.list_match_game_rows(match_id)
        Report.build(match, rows, spec, status) |> Report.write_json!(out_path)

        cond do
          match.status == "cancelled" ->
            # Either SPRT stopped it (status tells us) or someone cancelled from the UI
            finalize(match_id, spec, out_path, final_status(status, "cancelled"))

          status == "running" and sprt_decided?(spec, rows, match) ->
            Logger.info("Benchmark: SPRT reached a decision, stopping match early")
            stop_match(match_id)
            await_match(match_id, spec, out_path, "stopping_sprt")

          true ->
            await_match(match_id, spec, out_path, status)
        end

      {:match_completed, ^match_id} ->
        finalize(match_id, spec, out_path, final_status(status, "completed"))

      _other ->
        await_match(match_id, spec, out_path, status)
    after
      timeout ->
        # Watchdog: no news for a long time. Keep waiting while the match server
        # is alive (overnight runs must survive quiet stretches); if it died,
        # finalize with whatever the DB has so the run always produces output.
        case BotMatches.get_match_server(match_id) do
          {:ok, _pid} ->
            Logger.warning("Benchmark: no match updates for #{timeout}ms, still waiting")
            await_match(match_id, spec, out_path, status)

          {:error, :not_found} ->
            Logger.error("Benchmark: match server died, finalizing from DB state")
            finalize(match_id, spec, out_path, final_status(status, "cancelled"))
        end
    end
  end

  defp final_status("stopping_sprt", _default), do: "stopped_sprt"
  defp final_status(_status, default), do: default

  defp finalize(match_id, spec, out_path, status) do
    match = BotMatches.get_match!(match_id)
    rows = BotMatches.list_match_game_rows(match_id)
    report = Report.build(match, rows, spec, status)
    Report.write_json!(report, out_path)
    {:ok, report}
  end

  defp sprt_decided?(%Spec{sprt: nil}, _rows, _match), do: false

  defp sprt_decided?(%Spec{sprt: sprt_params}, rows, match) do
    if match.completed_games >= match.total_games do
      false
    else
      report_rows = Enum.map(rows, &Report.game_row/1)
      scored = Enum.reject(report_rows, &(&1["termination"] == "aborted"))
      wins_a = Enum.count(scored, &(&1["winner"] == "a"))
      wins_b = Enum.count(scored, &(&1["winner"] == "b"))
      draws = Enum.count(scored, &(&1["winner"] == "draw"))

      Bughouse.Benchmark.Stats.sprt(wins_a, draws, wins_b, sprt_params).decision != :continue
    end
  end

  defp stop_match(match_id) do
    case BotMatches.get_match_server(match_id) do
      {:ok, pid} -> BotMatchServer.cancel(pid)
      {:error, :not_found} -> :ok
    end
  end
end
