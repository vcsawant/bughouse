# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Bughouse.Repo.insert!(%Bughouse.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Bughouse.Repo
alias Bughouse.Schemas.Accounts.{Player, Bot}

# ── Internal Bot: Rusty ──────────────────────────────────────
#
# The Rust-based bughouse engine that runs as an Erlang Port.
# Supports dual mode (plays both seats of a team).

bot_username = "rusty"

player =
  case Repo.get_by(Player, username: bot_username) do
    nil ->
      %Player{}
      |> Player.changeset(%{
        username: bot_username,
        display_name: "Rusty",
        is_bot: true,
        guest: false,
        current_rating: 1200,
        peak_rating: 1200,
        total_games: 0,
        wins: 0,
        losses: 0,
        draws: 0
      })
      |> Repo.insert!()

    existing ->
      existing
  end

case Repo.get_by(Bot, player_id: player.id) do
  nil ->
    %Bot{}
    |> Bot.changeset(%{
      player_id: player.id,
      bot_type: "internal",
      status: "online",
      supported_modes: "both",
      single_rating: 1200,
      dual_rating: 1200,
      config: %{}
    })
    |> Repo.insert!()

  existing ->
    # Ensure bot is online (in case it was set offline previously)
    existing
    |> Bot.changeset(%{status: "online"})
    |> Repo.update!()
end

IO.puts("✓ Bot '#{bot_username}' seeded and set to online")
