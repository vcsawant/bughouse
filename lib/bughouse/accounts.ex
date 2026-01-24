defmodule Bughouse.Accounts do
  @moduledoc """
  The Accounts context - player management and social features.
  """

  import Ecto.Query, warn: false
  alias Bughouse.Repo
  alias Bughouse.Accounts.{Player, Friendship}

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
end
