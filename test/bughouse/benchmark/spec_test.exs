defmodule Bughouse.Benchmark.SpecTest do
  use ExUnit.Case, async: true

  alias Bughouse.Benchmark.Spec

  @required ~w(--engine-a /tmp/a --engine-b /tmp/b)

  describe "parse_args/1" do
    test "requires both engines" do
      assert {:error, message} = Spec.parse_args([])
      assert message =~ "--engine-a and --engine-b are required"

      assert {:error, _} = Spec.parse_args(~w(--engine-a /tmp/a))
    end

    test "applies defaults" do
      assert {:ok, spec} = Spec.parse_args(@required)

      assert spec.games == 20
      assert spec.time_control_ms == 60_000
      assert spec.parallel == 1
      assert spec.options_a == %{}
      assert spec.options_b == %{}
      assert spec.output_dir == "bench_results"
      assert spec.sprt == nil
    end

    test "engine names default to basenames, deduped when equal" do
      {:ok, spec} = Spec.parse_args(~w(--engine-a /x/engine_v1 --engine-b /y/engine_v2))
      assert spec.name_a == "engine_v1"
      assert spec.name_b == "engine_v2"

      {:ok, spec} = Spec.parse_args(~w(--engine-a /x/engine --engine-b /y/engine))
      assert spec.name_a == "engine-a"
      assert spec.name_b == "engine-b"
    end

    test "collects repeated engine options" do
      {:ok, spec} =
        Spec.parse_args(
          @required ++ ~w(--option-a Hash=128 --option-a Threads=2 --option-b QsCheckDropDepth=0)
        )

      assert spec.options_a == %{"Hash" => "128", "Threads" => "2"}
      assert spec.options_b == %{"QsCheckDropDepth" => "0"}
    end

    test "option values may contain =" do
      {:ok, spec} = Spec.parse_args(@required ++ ["--option-a", "EvalFile=nets/a=b.bin"])
      assert spec.options_a == %{"EvalFile" => "nets/a=b.bin"}
    end

    test "malformed option is an error" do
      assert {:error, message} = Spec.parse_args(@required ++ ~w(--option-a Hash128))
      assert message =~ "--option-a"
    end

    test "unknown flags are errors" do
      assert {:error, message} = Spec.parse_args(@required ++ ~w(--bogus 3))
      assert message =~ "--bogus"
    end

    test "bounds are validated" do
      assert {:error, message} = Spec.parse_args(@required ++ ~w(--games 0))
      assert message =~ "--games"

      assert {:error, _} = Spec.parse_args(@required ++ ~w(--games 1001))
      assert {:error, _} = Spec.parse_args(@required ++ ~w(--parallel 11))
      assert {:error, _} = Spec.parse_args(@required ++ ~w(--time-control 0))
    end

    test "sprt flag parses with defaults for missing keys" do
      {:ok, spec} = Spec.parse_args(@required ++ ["--sprt", "elo1=5"])
      assert spec.sprt == %{elo0: 0.0, elo1: 5.0, alpha: 0.05, beta: 0.05}
    end

    test "malformed sprt is an error" do
      assert {:error, message} = Spec.parse_args(@required ++ ["--sprt", "elo1=abc"])
      assert message =~ "--sprt"
    end
  end

  describe "parse_engine_option/1" do
    test "splits on the first =" do
      assert Spec.parse_engine_option("Hash=128") == {:ok, {"Hash", "128"}}
      assert Spec.parse_engine_option("Path=a=b") == {:ok, {"Path", "a=b"}}
    end

    test "rejects missing name or value" do
      assert Spec.parse_engine_option("Hash") == :error
      assert Spec.parse_engine_option("=128") == :error
      assert Spec.parse_engine_option("Hash=") == :error
    end
  end

  describe "parse_sprt/1" do
    test "full specification" do
      assert {:ok, %{elo0: -1.0, elo1: 4.0, alpha: 0.01, beta: 0.1}} =
               Spec.parse_sprt("elo0=-1,elo1=4,alpha=0.01,beta=0.1")
    end

    test "unknown keys are errors" do
      assert Spec.parse_sprt("gamma=1") == :error
    end
  end

  describe "config file merge" do
    setup do
      dir = System.tmp_dir!()
      path = Path.join(dir, "bench_spec_test_#{System.unique_integer([:positive])}.json")
      on_exit(fn -> File.rm(path) end)
      {:ok, path: path}
    end

    test "config supplies values, CLI overrides", %{path: path} do
      File.write!(
        path,
        Jason.encode!(%{
          engine_a: "/cfg/a",
          engine_b: "/cfg/b",
          games: 100,
          time_control_ms: 30_000,
          options_b: %{"Hash" => "64"}
        })
      )

      {:ok, spec} = Spec.parse_args(~w(--config #{path} --games 50))

      assert spec.engine_a == "/cfg/a"
      assert spec.engine_b == "/cfg/b"
      # CLI wins over config
      assert spec.games == 50
      # config wins over defaults
      assert spec.time_control_ms == 30_000
      assert spec.options_b == %{"Hash" => "64"}
    end

    test "invalid JSON is an error", %{path: path} do
      File.write!(path, "{nope")
      assert {:error, message} = Spec.parse_args(~w(--config #{path}))
      assert message =~ "invalid JSON"
    end

    test "missing file is an error" do
      assert {:error, message} = Spec.parse_args(~w(--config /nonexistent/x.json))
      assert message =~ "cannot read config"
    end
  end
end
