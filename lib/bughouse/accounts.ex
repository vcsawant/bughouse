defmodule Bughouse.Accounts do
  @moduledoc """
  The Accounts context - player management and social features.
  """

  import Ecto.Query, warn: false
  alias Bughouse.Repo
  alias Bughouse.Schemas.Accounts.{Player, Friendship, UserIdentity}
  alias Ecto.Multi
  require Logger

  @doc """
  Creates a guest player with auto-generated name.
  """
  def create_guest_player do
    display_name = "Guest_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"

    %Player{}
    |> Player.changeset(%{
      display_name: display_name,
      guest: true,
      current_rating: 1200,
      peak_rating: 1200
    })
    |> Repo.insert()
  end

  @doc """
  Gets a player by ID.
  """
  def get_player(id), do: Repo.get(Player, id)
  def get_player!(id), do: Repo.get!(Player, id)

  @doc """
  Updates player stats after game completion.
  """
  def update_player_stats(%Player{} = player, %{outcome: outcome, rating_change: rating_change}) do
    new_rating = player.current_rating + rating_change

    attrs = %{
      current_rating: new_rating,
      peak_rating: max(player.peak_rating, new_rating),
      total_games: player.total_games + 1
    }

    attrs =
      case outcome do
        :win -> Map.put(attrs, :wins, player.wins + 1)
        :loss -> Map.put(attrs, :losses, player.losses + 1)
        :draw -> Map.put(attrs, :draws, player.draws + 1)
        _ -> attrs
      end

    player
    |> Player.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a friendship request.
  """
  def create_friendship(player_id, friend_id) do
    %Friendship{}
    |> Friendship.changeset(%{
      player_id: player_id,
      friend_id: friend_id,
      status: :pending
    })
    |> Repo.insert()
  end

  @doc """
  Gets all accepted friends for a player.
  """
  def get_friends(player_id) do
    from(f in Friendship,
      where: (f.player_id == ^player_id or f.friend_id == ^player_id) and f.status == :accepted,
      preload: [:player, :friend]
    )
    |> Repo.all()
  end

  # OAuth Authentication Functions

  @doc """
  Finds existing OAuth user or determines if new user needs onboarding.
  Returns {:existing_user, player} or {:needs_onboarding, :new_user}
  """
  def find_or_prepare_oauth_user(provider, uid, email) do
    # Check if this specific OAuth identity already exists
    case get_player_by_oauth_identity(provider, uid) do
      %Player{} = player ->
        {:existing_user, player}

      nil ->
        # Check if email exists with another OAuth provider (for merging)
        case Repo.get_by(Player, email: email, guest: false) do
          %Player{} = player ->
            # Email exists, link this new OAuth provider to existing account
            # User data will be stored when they complete the OAuth callback
            link_oauth_identity(player, provider, uid, %{})
            {:existing_user, player}

          nil ->
            # Completely new user - needs to go through onboarding
            {:needs_onboarding, :new_user}
        end
    end
  end

  @doc """
  Links a new OAuth provider to an existing player account.
  """
  def link_oauth_identity(player, provider, uid, user_data) do
    # Check if identity already exists
    case Repo.get_by(UserIdentity, player_id: player.id, provider: to_string(provider)) do
      nil ->
        %UserIdentity{}
        |> UserIdentity.changeset(%{
          provider: to_string(provider),
          uid: uid,
          player_id: player.id,
          user_data: user_data
        })
        |> Repo.insert()

      identity ->
        # Identity exists, just return it
        {:ok, identity}
    end
  end

  @doc """
  Gets or creates player from OAuth identity.
  DEPRECATED: Use find_or_prepare_oauth_user/3 and create_oauth_player_with_username/4
  """
  def get_or_create_from_oauth(provider, user_params) do
    uid = user_params["sub"] || user_params["id"]

    case get_player_by_oauth_identity(provider, uid) do
      nil -> create_oauth_player(provider, user_params)
      player -> {:ok, player}
    end
  end

  @doc """
  Creates an authenticated player with user-chosen username and display name.
  """
  def create_oauth_player_with_username(provider, user_params, username, display_name) do
    player_params = %{
      username: username,
      display_name: display_name,
      email: user_params["email"],
      guest: false,
      current_rating: 1200,
      peak_rating: 1200,
      total_games: 0,
      wins: 0,
      losses: 0,
      draws: 0,
      email_confirmed_at: DateTime.utc_now()
    }

    Multi.new()
    |> Multi.insert(:player, Player.changeset(%Player{}, player_params))
    |> Multi.insert(:identity, fn %{player: player} ->
      %UserIdentity{}
      |> UserIdentity.changeset(%{
        provider: to_string(provider),
        uid: user_params["sub"] || user_params["id"],
        player_id: player.id,
        access_token: nil,
        user_data: user_params
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{player: player}} -> {:ok, player}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Creates an authenticated player from OAuth provider data.
  DEPRECATED: Use create_oauth_player_with_username/4
  """
  def create_oauth_player(provider, user_params) do
    display_name = generate_display_name_from_oauth(user_params)

    player_params = %{
      email: user_params["email"],
      display_name: display_name,
      guest: false,
      current_rating: 1200,
      peak_rating: 1200,
      total_games: 0,
      wins: 0,
      losses: 0,
      draws: 0,
      email_confirmed_at: DateTime.utc_now()
    }

    Multi.new()
    |> Multi.insert(:player, Player.changeset(%Player{}, player_params))
    |> Multi.insert(:identity, fn %{player: player} ->
      %UserIdentity{}
      |> UserIdentity.changeset(%{
        provider: to_string(provider),
        uid: user_params["sub"] || user_params["id"],
        player_id: player.id,
        access_token: nil,
        user_data: user_params
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{player: player}} -> {:ok, player}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Gets player by OAuth identity.
  """
  def get_player_by_oauth_identity(provider, uid) do
    query =
      from ui in UserIdentity,
        where: ui.provider == ^to_string(provider) and ui.uid == ^uid,
        join: p in assoc(ui, :player),
        select: p

    Repo.one(query)
  end

  @doc """
  Checks if a username is available.
  """
  def username_available?(username) do
    case Repo.get_by(Player, username: username) do
      nil -> true
      _player -> false
    end
  end

  @doc """
  Updates a player's display name only.
  """
  def update_player_display_name(%Player{} = player, display_name) do
    player
    |> Player.changeset(%{display_name: display_name})
    |> Repo.update()
  end

  @doc """
  Gets a player with preloaded OAuth identities.
  """
  def get_player_with_identities(player_id) do
    from(p in Player,
      where: p.id == ^player_id,
      preload: [:user_identities]
    )
    |> Repo.one()
  end

  @doc """
  Suggests a username from OAuth user params.
  Returns a clean, URL-safe username suggestion (not guaranteed to be available).
  """
  def suggest_username_from_oauth(user_params) do
    base =
      cond do
        user_params["email"] ->
          user_params["email"]
          |> String.split("@")
          |> List.first()
          |> String.downcase()

        user_params["given_name"] ->
          user_params["given_name"]
          |> String.downcase()

        user_params["name"] ->
          user_params["name"]
          |> String.split()
          |> List.first()
          |> String.downcase()

        true ->
          "user"
      end

    # Clean up: remove non-alphanumeric (except underscore), limit length
    base
    |> String.replace(~r/[^a-z0-9_]/, "")
    |> String.slice(0..19)
  end

  @doc """
  Suggests a display name from OAuth user params.
  """
  def suggest_display_name_from_oauth(user_params) do
    cond do
      user_params["given_name"] && user_params["family_name"] ->
        "#{user_params["given_name"]} #{user_params["family_name"]}"

      user_params["name"] ->
        user_params["name"]

      user_params["email"] ->
        user_params["email"] |> String.split("@") |> List.first()

      true ->
        "Player"
    end
  end

  # DEPRECATED: Display names are no longer forced to be unique
  defp generate_display_name_from_oauth(user_params) do
    suggest_display_name_from_oauth(user_params)
  end

  # DEPRECATED: Display names are no longer forced to be unique
  defp ensure_unique_display_name(base_name, _attempt \\ 0) do
    base_name
  end
end
