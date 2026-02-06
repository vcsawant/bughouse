defmodule Bughouse.Repo.Migrations.RemovePositionFieldsFromGamePlayers do
  use Ecto.Migration

  def change do
    alter table(:game_players) do
      remove :position, :string
      remove :color, :string
      remove :board, :integer
    end
  end
end
