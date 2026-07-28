defmodule Bughouse.Benchmark.Spec do
  @moduledoc """
  Benchmark run specification: two engine binaries, game count, time control,
  per-engine UBI options, and optional SPRT early-stopping parameters.

  Built from `mix benchmark` CLI flags, optionally merged over a JSON config
  file (`--config path.json`, CLI flags win).
  """

  defstruct engine_a: nil,
            engine_b: nil,
            name_a: nil,
            name_b: nil,
            games: 20,
            time_control_ms: 60_000,
            parallel: 1,
            options_a: %{},
            options_b: %{},
            output_dir: "bench_results",
            sprt: nil

  @type t :: %__MODULE__{}

  @cli_switches [
    engine_a: :string,
    engine_b: :string,
    games: :integer,
    time_control: :integer,
    option_a: :keep,
    option_b: :keep,
    parallel: :integer,
    output_dir: :string,
    name_a: :string,
    name_b: :string,
    sprt: :string,
    config: :string
  ]

  @sprt_defaults %{elo0: 0.0, elo1: 10.0, alpha: 0.05, beta: 0.05}

  @doc """
  Parses CLI arguments into a spec. Returns `{:ok, spec}` or `{:error, message}`.
  """
  @spec parse_args([String.t()]) :: {:ok, t()} | {:error, String.t()}
  def parse_args(argv) do
    case OptionParser.parse(argv, strict: @cli_switches) do
      {opts, [], []} ->
        with {:ok, base} <- load_base_config(opts[:config]),
             {:ok, spec} <- build_spec(base, opts) do
          validate_bounds(spec)
        end

      {_opts, rest, invalid} ->
        problems =
          Enum.map(invalid, fn {flag, _} -> "invalid flag or value: #{flag}" end) ++
            Enum.map(rest, fn arg -> "unexpected argument: #{arg}" end)

        {:error, Enum.join(problems, "; ")}
    end
  end

  @doc """
  Loads a JSON config file into a map with the same keys as the struct.
  """
  @spec load_config(String.t()) :: {:ok, map()} | {:error, String.t()}
  def load_config(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, %{} = map} <- Jason.decode(contents) do
      {:ok, map}
    else
      {:ok, _non_map} ->
        {:error, "config file must contain a JSON object: #{path}"}

      {:error, %Jason.DecodeError{} = err} ->
        {:error, "invalid JSON in #{path}: #{Exception.message(err)}"}

      {:error, reason} ->
        {:error, "cannot read config #{path}: #{inspect(reason)}"}
    end
  end

  @doc """
  Parses a `Name=Value` engine option. The value may itself contain `=`.
  """
  @spec parse_engine_option(String.t()) :: {:ok, {String.t(), String.t()}} | :error
  def parse_engine_option(str) do
    case String.split(str, "=", parts: 2) do
      [name, value] when name != "" and value != "" -> {:ok, {name, value}}
      _ -> :error
    end
  end

  @doc """
  Parses SPRT parameters like `"elo0=0,elo1=10,alpha=0.05,beta=0.05"`.
  All keys are optional; missing keys use the defaults above.
  """
  @spec parse_sprt(String.t()) :: {:ok, map()} | :error
  def parse_sprt(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, @sprt_defaults}, fn part, {:ok, acc} ->
      with [key, value] <- String.split(part, "=", parts: 2),
           key_atom when key_atom != nil <- sprt_key(String.trim(key)),
           {num, ""} <- Float.parse(String.trim(value)) do
        {:cont, {:ok, Map.put(acc, key_atom, num)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp sprt_key("elo0"), do: :elo0
  defp sprt_key("elo1"), do: :elo1
  defp sprt_key("alpha"), do: :alpha
  defp sprt_key("beta"), do: :beta
  defp sprt_key(_), do: nil

  @doc """
  Filesystem validation (engine binaries exist). Kept out of `parse_args/1`
  so parsing stays pure for tests.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = spec) do
    cond do
      not File.exists?(spec.engine_a) -> {:error, "engine A binary not found: #{spec.engine_a}"}
      not File.exists?(spec.engine_b) -> {:error, "engine B binary not found: #{spec.engine_b}"}
      true -> :ok
    end
  end

  ## Internal

  defp load_base_config(nil), do: {:ok, %{}}
  defp load_base_config(path), do: load_config(path)

  defp build_spec(base, opts) do
    with {:ok, options_a} <- collect_options(opts, :option_a, base["options_a"]),
         {:ok, options_b} <- collect_options(opts, :option_b, base["options_b"]),
         {:ok, sprt} <- resolve_sprt(opts[:sprt], base["sprt"]) do
      engine_a = opts[:engine_a] || base["engine_a"]
      engine_b = opts[:engine_b] || base["engine_b"]

      if engine_a == nil or engine_b == nil do
        {:error, "--engine-a and --engine-b are required (via flags or config file)"}
      else
        {name_a, name_b} =
          default_names(
            opts[:name_a] || base["name_a"],
            opts[:name_b] || base["name_b"],
            engine_a,
            engine_b
          )

        {:ok,
         %__MODULE__{
           engine_a: engine_a,
           engine_b: engine_b,
           name_a: name_a,
           name_b: name_b,
           games: opts[:games] || base["games"] || 20,
           time_control_ms: opts[:time_control] || base["time_control_ms"] || 60_000,
           parallel: opts[:parallel] || base["parallel"] || 1,
           options_a: options_a,
           options_b: options_b,
           output_dir: opts[:output_dir] || base["output_dir"] || "bench_results",
           sprt: sprt
         }}
      end
    end
  end

  defp collect_options(opts, key, base_options) do
    cli_opts = Keyword.get_values(opts, key)

    if cli_opts == [] do
      {:ok, base_options || %{}}
    else
      Enum.reduce_while(cli_opts, {:ok, %{}}, fn str, {:ok, acc} ->
        case parse_engine_option(str) do
          {:ok, {name, value}} -> {:cont, {:ok, Map.put(acc, name, value)}}
          :error -> {:halt, {:error, "malformed #{cli_flag(key)} (want Name=Value): #{str}"}}
        end
      end)
    end
  end

  defp cli_flag(:option_a), do: "--option-a"
  defp cli_flag(:option_b), do: "--option-b"

  defp resolve_sprt(nil, nil), do: {:ok, nil}

  defp resolve_sprt(nil, %{} = base) do
    if Enum.all?(base, fn {k, v} -> sprt_key(k) != nil and is_number(v) end) do
      {:ok, Map.merge(@sprt_defaults, Map.new(base, fn {k, v} -> {sprt_key(k), v * 1.0} end))}
    else
      {:error, "invalid sprt config (want numeric elo0/elo1/alpha/beta): #{inspect(base)}"}
    end
  end

  defp resolve_sprt(cli_string, _base) do
    case parse_sprt(cli_string) do
      {:ok, sprt} -> {:ok, sprt}
      :error -> {:error, "malformed --sprt (want e.g. \"elo0=0,elo1=10,alpha=0.05,beta=0.05\")"}
    end
  end

  defp default_names(name_a, name_b, engine_a, engine_b) do
    name_a = name_a || Path.basename(engine_a)
    name_b = name_b || Path.basename(engine_b)

    if name_a == name_b do
      {name_a <> "-a", name_b <> "-b"}
    else
      {name_a, name_b}
    end
  end

  defp validate_bounds(spec) do
    cond do
      spec.games not in 1..1000 -> {:error, "--games must be between 1 and 1000"}
      spec.parallel not in 1..10 -> {:error, "--parallel must be between 1 and 10"}
      spec.time_control_ms <= 0 -> {:error, "--time-control must be a positive integer (ms)"}
      true -> {:ok, spec}
    end
  end
end
