defmodule Bughouse.Repo.Migrations.AddResultReasonToBotMatchGames do
  use Ecto.Migration

  def change do
    alter table(:bot_match_games) do
      add :result_reason, :string, null: true
    end
  end
end
