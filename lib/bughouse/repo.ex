defmodule Bughouse.Repo do
  use Ecto.Repo,
    otp_app: :bughouse,
    adapter: Ecto.Adapters.Postgres
end
