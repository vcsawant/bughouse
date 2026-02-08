defmodule Bughouse.Release do
  @moduledoc """
  Release tasks for running migrations and seeds in production.

  Usage from Fly.io:

      fly ssh console -C "/app/bin/migrate"
      fly ssh console -C "/app/bin/seed"
  """

  @app :bughouse

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seeds_file = priv_path_for(repo, "seeds.exs")

          if File.regular?(seeds_file) do
            Code.eval_file(seeds_file)
          end
        end)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end

  defp priv_path_for(repo, filename) do
    app = Keyword.get(repo.config(), :otp_app)
    repo_underscore = repo |> Module.split() |> List.last() |> Macro.underscore()
    Application.app_dir(app, ["priv", repo_underscore, filename])
  end
end
