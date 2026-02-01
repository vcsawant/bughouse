defmodule Bughouse.Repo.Migrations.AddOauthToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :email_confirmed_at, :utc_datetime
    end

    # Email should be unique for non-guest users
    create unique_index(:players, [:email],
             where: "guest = false",
             name: :players_email_index
           )
  end
end
