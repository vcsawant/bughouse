defmodule Bughouse.Repo.Migrations.AddParallelGamesToBotMatches do
  use Ecto.Migration

  def change do
    alter table(:bot_matches) do
      add :parallel_games, :integer, null: false, default: 1
    end
  end
end
