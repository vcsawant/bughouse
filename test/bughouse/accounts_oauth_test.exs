defmodule Bughouse.AccountsOAuthTest do
  use Bughouse.DataCase

  alias Bughouse.Accounts
  alias Bughouse.Schemas.Accounts.UserIdentity

  describe "OAuth authentication" do
    @google_user_params %{
      "sub" => "google-user-123",
      "email" => "test@example.com",
      "given_name" => "John",
      "family_name" => "Doe",
      "name" => "John Doe"
    }

    test "create_oauth_player_with_username/4 creates player with OAuth identity" do
      assert {:ok, player} =
               Accounts.create_oauth_player_with_username(
                 "google",
                 @google_user_params,
                 "johndoe",
                 "John Doe"
               )

      assert player.username == "johndoe"
      assert player.email == "test@example.com"
      assert player.display_name == "John Doe"
      assert player.guest == false
      assert player.current_rating == 1200
      assert player.email_confirmed_at != nil

      # Check identity was created
      identity = Repo.get_by(UserIdentity, player_id: player.id)
      assert identity.provider == "google"
      assert identity.uid == "google-user-123"
    end

    test "create_oauth_player_with_username/4 allows duplicate display names" do
      # Create first player
      {:ok, player1} =
        Accounts.create_oauth_player_with_username(
          "google",
          @google_user_params,
          "johndoe1",
          "John Doe"
        )

      assert player1.display_name == "John Doe"

      # Create second player with same display name but different username and email
      params2 =
        @google_user_params
        |> Map.put("sub", "google-user-456")
        |> Map.put("email", "john.doe2@example.com")

      {:ok, player2} =
        Accounts.create_oauth_player_with_username("google", params2, "johndoe2", "John Doe")

      # Same display name is allowed
      assert player2.display_name == "John Doe"
      assert player1.id != player2.id
      # But different usernames
      assert player1.username != player2.username
    end

    test "create_oauth_player_with_username/4 enforces unique usernames" do
      # Create first player
      {:ok, _player1} =
        Accounts.create_oauth_player_with_username(
          "google",
          @google_user_params,
          "johndoe",
          "John Doe"
        )

      # Try to create second player with same username
      params2 =
        @google_user_params
        |> Map.put("sub", "google-user-456")
        |> Map.put("email", "john.doe2@example.com")

      assert {:error, changeset} =
               Accounts.create_oauth_player_with_username(
                 "google",
                 params2,
                 "johndoe",
                 "Jane Doe"
               )

      assert "has already been taken" in errors_on(changeset).username
    end

    test "find_or_prepare_oauth_user/3 returns existing player if identity exists" do
      {:ok, player1} =
        Accounts.create_oauth_player_with_username(
          "google",
          @google_user_params,
          "johndoe",
          "John Doe"
        )

      # Try to find with same OAuth ID
      assert {:existing_user, player2} =
               Accounts.find_or_prepare_oauth_user(
                 "google",
                 "google-user-123",
                 "test@example.com"
               )

      assert player1.id == player2.id
    end

    test "find_or_prepare_oauth_user/3 returns needs_onboarding for new user" do
      assert {:needs_onboarding, :new_user} =
               Accounts.find_or_prepare_oauth_user(
                 "google",
                 "google-user-new",
                 "newuser@example.com"
               )
    end

    test "find_or_prepare_oauth_user/3 merges accounts by email across providers" do
      # Create user with Google
      {:ok, google_player} =
        Accounts.create_oauth_player_with_username(
          "google",
          @google_user_params,
          "johndoe",
          "John Doe"
        )

      # Try to login with GitHub (same email, different provider)
      assert {:existing_user, github_player} =
               Accounts.find_or_prepare_oauth_user(
                 "github",
                 "github-user-123",
                 "test@example.com"
               )

      # Should be the same player
      assert google_player.id == github_player.id

      # Should have identities for both providers
      identities = Repo.all(from ui in UserIdentity, where: ui.player_id == ^google_player.id)
      assert length(identities) == 2
      providers = Enum.map(identities, & &1.provider)
      assert "google" in providers
      assert "github" in providers
    end

    test "get_player_by_oauth_identity/2 finds player by provider and uid" do
      {:ok, created_player} =
        Accounts.create_oauth_player_with_username(
          "google",
          @google_user_params,
          "johndoe",
          "John Doe"
        )

      player = Accounts.get_player_by_oauth_identity("google", "google-user-123")

      assert player.id == created_player.id
    end

    test "get_player_by_oauth_identity/2 returns nil if not found" do
      assert Accounts.get_player_by_oauth_identity("google", "nonexistent") == nil
    end

    test "username_available?/1 returns true for available username" do
      assert Accounts.username_available?("available_username")
    end

    test "username_available?/1 returns false for taken username" do
      {:ok, _player} =
        Accounts.create_oauth_player_with_username(
          "google",
          @google_user_params,
          "taken_username",
          "John Doe"
        )

      refute Accounts.username_available?("taken_username")
    end

    test "suggest_username_from_oauth/1 uses email username" do
      params = %{"email" => "john.smith@example.com"}
      assert Accounts.suggest_username_from_oauth(params) == "johnsmith"
    end

    test "suggest_username_from_oauth/1 uses given_name" do
      params = %{"given_name" => "Jane"}
      assert Accounts.suggest_username_from_oauth(params) == "jane"
    end

    test "suggest_username_from_oauth/1 cleans up special characters" do
      params = %{"email" => "john+test@example.com"}
      # Should remove the '+' character
      assert Accounts.suggest_username_from_oauth(params) == "johntest"
    end

    test "suggest_display_name_from_oauth/1 uses name components" do
      params = %{
        "given_name" => "Jane",
        "family_name" => "Smith"
      }

      assert Accounts.suggest_display_name_from_oauth(params) == "Jane Smith"
    end

    test "suggest_display_name_from_oauth/1 falls back to full name" do
      params = %{"name" => "Bob Jones"}
      assert Accounts.suggest_display_name_from_oauth(params) == "Bob Jones"
    end

    test "suggest_display_name_from_oauth/1 falls back to email username" do
      params = %{"email" => "alice@example.com"}
      assert Accounts.suggest_display_name_from_oauth(params) == "alice"
    end
  end
end
