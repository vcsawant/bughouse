defmodule Bughouse.Repo.Migrations.AddEnginePathToBots do
  use Ecto.Migration

  def change do
    alter table(:bots) do
      add :engine_path, :string, null: true
    end
  end
end
