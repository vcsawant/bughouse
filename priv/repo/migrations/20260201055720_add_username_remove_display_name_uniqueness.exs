defmodule Bughouse.Repo.Migrations.AddUsernameRemoveDisplayNameUniqueness do
  use Ecto.Migration

  def change do
    # Remove display_name uniqueness constraint
    drop_if_exists index(:players, [:display_name])

    # Add username field
    alter table(:players) do
      add :username, :string
    end

    # Username unique for authenticated users only (guests have NULL username)
    create unique_index(:players, [:username],
             where: "guest = false AND username IS NOT NULL",
             name: :players_username_index
           )
  end
end
