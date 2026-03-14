defmodule BughouseWeb.BotController do
  use BughouseWeb, :controller

  alias Bughouse.Bots

  def index(conn, _params) do
    bots = Bots.list_public_bots()

    json(conn, %{
      bots:
        Enum.map(bots, fn bot ->
          %{
            id: bot.id,
            name: bot.name,
            display_name: bot.display_name,
            rating: bot.current_rating,
            status: bot.status,
            games_played: bot.games_played,
            owner: bot.player.display_name
          }
        end)
    })
  end

  def show(conn, %{"id" => id_or_name}) do
    bot = find_bot(id_or_name)

    case bot do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Bot not found"})

      bot ->
        bot = Bughouse.Repo.preload(bot, :player)

        json(conn, %{
          bot: %{
            id: bot.id,
            name: bot.name,
            display_name: bot.display_name,
            description: bot.description,
            bot_type: bot.bot_type,
            rating: bot.current_rating,
            status: bot.status,
            health_status: bot.health_status,
            games_played: bot.games_played,
            games_won: bot.games_won,
            is_public: bot.is_public,
            owner: %{
              display_name: bot.player.display_name,
              username: bot.player.username
            }
          }
        })
    end
  end

  # Accept UUID or bot name
  defp find_bot(id_or_name) do
    case Ecto.UUID.cast(id_or_name) do
      {:ok, uuid} -> Bots.get_bot(uuid)
      :error -> Bots.get_bot_by_name(id_or_name)
    end
  end
end
