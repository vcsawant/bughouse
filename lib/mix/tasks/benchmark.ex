defmodule Mix.Tasks.Benchmark do
  @moduledoc """
  Runs a headless bot-vs-bot benchmark match between two UBI engine binaries.

  ## Usage

      mix benchmark --engine-a PATH --engine-b PATH [options]

  ## Options

      --engine-a PATH       Engine A binary (required)
      --engine-b PATH       Engine B binary (required; may equal --engine-a)
      --games N             Number of games (default 20, max 1000)
      --time-control MS     Per-player clock in milliseconds (default 60000)
      --option-a Name=Val   UBI setoption for engine A (repeatable)
      --option-b Name=Val   UBI setoption for engine B (repeatable)
      --parallel N          Games to run concurrently (default 1, max 10)
      --output-dir PATH     Results directory (default bench_results)
      --name-a NAME         Label for engine A (default: binary basename)
      --name-b NAME         Label for engine B (default: binary basename)
      --sprt PARAMS         Enable SPRT early stopping, e.g.
                            "elo0=0,elo1=10,alpha=0.05,beta=0.05"
      --config PATH         JSON config file; CLI flags override its values

  ## Examples

      mix benchmark --engine-a ../bughouse-engine/target/release/bughouse_engine \\
                    --engine-b ../bughouse-engine/target/release/bughouse_engine \\
                    --games 4 --time-control 60000

      mix benchmark --engine-a ./baseline --engine-b ./baseline \\
                    --option-b QsCheckDropDepth=0 --games 100 --sprt "elo0=0,elo1=10"

  Results are written to `<output-dir>/<match_id>/results.json` (rewritten after
  every game) with per-game engine logs alongside. See bench/README.md.
  """
  use Mix.Task

  @shortdoc "Run a headless bot-vs-bot engine benchmark match"

  alias Bughouse.Benchmark.{Report, Runner, Spec}

  @impl true
  def run(argv) do
    spec =
      case Spec.parse_args(argv) do
        {:ok, spec} -> spec
        {:error, message} -> usage_error(message)
      end

    configure_app(spec)
    Mix.Task.run("app.start")

    case Spec.validate(spec) do
      :ok -> :ok
      {:error, message} -> Mix.raise(message)
    end

    case Runner.run(spec) do
      {:ok, report} ->
        Mix.shell().info(Report.render_text(report))

        Mix.shell().info(
          "Results: #{Path.join([spec.output_dir, report["match_id"], "results.json"])}"
        )

      {:error, reason} ->
        Mix.raise("Benchmark failed: #{inspect(reason)}")
    end
  end

  defp configure_app(spec) do
    # Never bind the web port from the benchmark task, even if the environment
    # would normally start the endpoint server (e.g. PHX_SERVER is set).
    endpoint_cfg = Application.get_env(:bughouse, BughouseWeb.Endpoint, [])

    Application.put_env(
      :bughouse,
      BughouseWeb.Endpoint,
      Keyword.put(endpoint_cfg, :server, false)
    )

    # Engine logs go next to results.json: BotEngine.Server already nests logs
    # under <game_log_path>/<match_id>/. Bot-vs-bot needs 2 engines per game.
    bot_engine_cfg = Application.get_env(:bughouse, :bot_engine) || []

    bot_engine_cfg =
      bot_engine_cfg
      |> Keyword.put(:game_log_path, Path.expand(spec.output_dir))
      |> Keyword.update(:max_concurrent, 2 * spec.parallel, &max(&1, 2 * spec.parallel))

    Application.put_env(:bughouse, :bot_engine, bot_engine_cfg)
  end

  @spec usage_error(String.t()) :: no_return()
  defp usage_error(message) do
    Mix.shell().error("mix benchmark: #{message}\n")
    Mix.shell().info(@moduledoc)
    Mix.raise("invalid arguments")
  end
end
