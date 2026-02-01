defmodule Bughouse.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider, :string, null: false
      add :uid, :string, null: false
      add :player_id, references(:players, type: :binary_id, on_delete: :delete_all), null: false
      add :access_token, :string
      add :refresh_token, :string
      add :expires_at, :bigint
      add :user_data, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_identities, [:provider, :uid])
    create index(:user_identities, [:player_id])
  end
end
