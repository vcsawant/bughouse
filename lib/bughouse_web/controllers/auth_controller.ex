defmodule BughouseWeb.AuthController do
  use BughouseWeb, :controller
  alias Bughouse.Accounts
  require Logger

  plug :put_layout, html: {BughouseWeb.Layouts, :app}

  def login(conn, _params) do
    render(conn, :login)
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end

  def request(conn, %{"provider" => "google"}) do
    config = Application.get_env(:bughouse, :oauth)[:google]

    Logger.debug("OAuth config: #{inspect(config)}")

    case Assent.Strategy.Google.authorize_url(config) do
      {:ok, %{url: url, session_params: session_params} = result} ->
        Logger.debug("authorize_url result: #{inspect(result)}")
        # Use atom key, not string key
        state = session_params[:state]
        Logger.debug("OAuth request - storing state: #{inspect(state)}")

        conn
        |> put_session(:oauth_state, state)
        # Force session to be written
        |> configure_session(renew: true)
        |> redirect(external: url)

      {:error, error} ->
        Logger.error("OAuth request failed: #{inspect(error)}")

        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/login")
    end
  end

  def callback(conn, %{"provider" => "google", "code" => _code, "state" => state} = params) do
    config = Application.get_env(:bughouse, :oauth)[:google]
    stored_state = get_session(conn, :oauth_state)

    Logger.debug("OAuth callback - received state: #{state}")
    Logger.debug("OAuth callback - stored state: #{inspect(stored_state)}")

    if state != stored_state do
      Logger.error("OAuth state mismatch! Received: #{state}, Stored: #{inspect(stored_state)}")

      conn
      |> put_flash(:error, "Invalid state parameter. Please try signing in again.")
      |> redirect(to: ~p"/login")
    else
      # Add session_params to config for callback
      session_params = %{state: stored_state}
      callback_config = config ++ [session_params: session_params]

      case Assent.Strategy.Google.callback(callback_config, params) do
        {:ok, %{user: user_params}} ->
          handle_oauth_success(conn, "google", user_params)

        {:error, error} ->
          Logger.error("OAuth callback failed: #{inspect(error)}")

          conn
          |> put_flash(:error, "Authentication failed. Please try again.")
          |> redirect(to: ~p"/login")
      end
    end
  end

  defp handle_oauth_success(conn, provider, user_params) do
    uid = user_params["sub"] || user_params["id"]
    email = user_params["email"]

    case Accounts.find_or_prepare_oauth_user(provider, uid, email) do
      {:existing_user, player} ->
        # User already has an account, log them in
        Logger.info("OAuth login successful for existing player: #{player.id}")

        conn
        |> delete_session(:oauth_state)
        |> put_session(:current_player_id, player.id)
        |> put_session(:authenticated, true)
        |> put_flash(:info, "Welcome back, #{player.display_name}!")
        |> redirect(to: ~p"/")

      {:needs_onboarding, :new_user} ->
        # New user needs to pick username and display name
        Logger.info("New OAuth user needs onboarding: #{email}")

        conn
        |> delete_session(:oauth_state)
        |> put_session(:pending_oauth, %{
          "provider" => provider,
          "user_params" => user_params
        })
        |> redirect(to: ~p"/onboarding/username")
    end
  end
end
