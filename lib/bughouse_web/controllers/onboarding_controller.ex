defmodule BughouseWeb.OnboardingController do
  use BughouseWeb, :controller
  alias Bughouse.Accounts
  require Logger

  plug :put_layout, html: {BughouseWeb.Layouts, :app}

  def username(conn, _params) do
    # Check if there's pending OAuth in session
    case get_session(conn, :pending_oauth) do
      nil ->
        conn
        |> put_flash(:error, "Invalid onboarding session. Please sign in again.")
        |> redirect(to: ~p"/login")

      pending_oauth ->
        user_params = pending_oauth["user_params"]

        # Generate suggestions from OAuth data
        suggested_username = Accounts.suggest_username_from_oauth(user_params)
        suggested_display_name = Accounts.suggest_display_name_from_oauth(user_params)

        render(conn, :username,
          suggested_username: suggested_username,
          suggested_display_name: suggested_display_name,
          errors: %{}
        )
    end
  end

  def create_username(conn, %{"username" => username, "display_name" => display_name}) do
    pending_oauth = get_session(conn, :pending_oauth)

    if is_nil(pending_oauth) do
      conn
      |> put_flash(:error, "Invalid onboarding session. Please sign in again.")
      |> redirect(to: ~p"/login")
    else
      provider = pending_oauth["provider"]
      user_params = pending_oauth["user_params"]

      case Accounts.create_oauth_player_with_username(
             provider,
             user_params,
             username,
             display_name
           ) do
        {:ok, player} ->
          Logger.info("Created OAuth player with username: #{username}")

          conn
          |> delete_session(:pending_oauth)
          |> put_session(:current_player_id, player.id)
          |> put_session(:authenticated, true)
          |> put_flash(:info, "Welcome to Bughouse Chess, @#{username}!")
          |> redirect(to: ~p"/")

        {:error, %Ecto.Changeset{} = changeset} ->
          errors = changeset_errors_to_map(changeset)

          user_params = pending_oauth["user_params"]
          suggested_username = Accounts.suggest_username_from_oauth(user_params)
          suggested_display_name = Accounts.suggest_display_name_from_oauth(user_params)

          render(conn, :username,
            suggested_username: suggested_username,
            suggested_display_name: suggested_display_name,
            errors: errors,
            username: username,
            display_name: display_name
          )
      end
    end
  end

  defp changeset_errors_to_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
