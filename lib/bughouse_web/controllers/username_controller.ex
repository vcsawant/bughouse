defmodule BughouseWeb.UsernameController do
  use BughouseWeb, :controller
  alias Bughouse.Accounts

  def check_availability(conn, %{"username" => username}) do
    # Validate format before checking database
    valid_format = Regex.match?(~r/^[a-zA-Z0-9_]{3,20}$/, username)

    available =
      if valid_format do
        Accounts.username_available?(username)
      else
        false
      end

    json(conn, %{available: available})
  end
end
