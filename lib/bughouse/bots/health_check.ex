defmodule Bughouse.Bots.HealthCheck do
  @moduledoc """
  Health-check module for bot engines.

  Internal bots are assumed healthy. External bots are checked via
  HTTP GET to `{endpoint_base}/game/health_check`.
  """

  require Logger

  alias Bughouse.Schemas.Accounts.Bot

  @health_check_timeout 5_000

  @doc """
  Checks health of a bot engine.

  - Internal bots: always returns `{:ok, "healthy"}`
  - External bots without endpoint_base: returns `{:ok, "unhealthy"}`
  - External bots with endpoint_base: performs HTTP GET to the health endpoint
  """
  def check(%Bot{bot_type: "internal"}), do: {:ok, "healthy"}

  def check(%Bot{bot_type: "external", endpoint_base: nil}), do: {:ok, "unhealthy"}
  def check(%Bot{bot_type: "external", endpoint_base: ""}), do: {:ok, "unhealthy"}

  def check(%Bot{bot_type: "external"} = bot) do
    url = health_check_url(bot)
    Logger.info("Health check for external bot #{bot.name} at #{url}")

    case http_get(url) do
      {:ok, status, body} when status in 200..299 ->
        Logger.info("Health check OK for #{bot.name}: #{status} #{body}")
        {:ok, "healthy"}

      {:ok, status, body} ->
        Logger.warning("Health check failed for #{bot.name}: HTTP #{status} #{body}")
        {:ok, "unhealthy"}

      {:error, reason} ->
        Logger.warning("Health check error for #{bot.name}: #{inspect(reason)}")
        {:ok, "unhealthy"}
    end
  end

  @doc """
  Returns the health check URL for a bot, or nil for internal bots.
  """
  def health_check_url(%Bot{bot_type: "internal"}), do: nil

  def health_check_url(%Bot{endpoint_base: nil}), do: nil

  def health_check_url(%Bot{endpoint_base: endpoint_base}) do
    "#{String.trim_trailing(endpoint_base, "/")}/game/health_check"
  end

  @doc """
  Returns the WebSocket game connection URL for a bot, or nil for internal bots.

  Converts the HTTP-scheme endpoint_base to the corresponding WS scheme:
  `https://` → `wss://`, `http://` → `ws://`.
  """
  def game_url(%Bot{bot_type: "internal"}, _game_id), do: nil

  def game_url(%Bot{endpoint_base: nil}, _game_id), do: nil

  def game_url(%Bot{endpoint_base: endpoint_base}, game_id) do
    base = String.trim_trailing(endpoint_base, "/")
    ws_base = to_ws_scheme(base)
    "#{ws_base}/game/#{game_id}"
  end

  defp to_ws_scheme("https://" <> rest), do: "wss://" <> rest
  defp to_ws_scheme("http://" <> rest), do: "ws://" <> rest
  defp to_ws_scheme(other), do: "ws://" <> other

  # Uses Erlang's built-in :httpc (from :inets) for a simple GET request.
  defp http_get(url) do
    url_charlist = String.to_charlist(url)

    case :httpc.request(:get, {url_charlist, []}, [timeout: @health_check_timeout], []) do
      {:ok, {{_http_version, status_code, _reason}, _headers, body}} ->
        {:ok, status_code, List.to_string(body)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
