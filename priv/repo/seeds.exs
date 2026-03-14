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
      owner_id: player.id,
      name: bot_username,
      display_name: "Rusty",
      description: "Built-in Rust bughouse engine",
      bot_type: "internal",
      status: "online",
      is_public: true,
      is_active: true,
      config: %{},
      default_options: Bughouse.Bots.strength_presets()["balanced"]
    })
    |> Repo.insert!()

  existing ->
    # Ensure bot is online (in case it was set offline previously)
    existing
    |> Bot.status_changeset(%{status: "online"})
    |> Repo.update!()
end

IO.puts("✓ Bot '#{bot_username}' seeded and set to online")
