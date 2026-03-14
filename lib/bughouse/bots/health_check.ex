defmodule Bughouse.Bots.HealthCheck do
  @moduledoc """
  Stub health-check module for bot engines.

  Internal bots are assumed healthy. External bots require a future
  WebSocket client to verify reachability — for now they report "unknown".
  """

  require Logger

  alias Bughouse.Schemas.Accounts.Bot

  @doc """
  Checks health of a bot engine.

  - Internal bots: always returns `{:ok, "healthy"}`
  - External bots without endpoint_base: returns `{:ok, "unhealthy"}`
  - External bots with endpoint_base: logs and returns `{:ok, "unknown"}` (TODO: real check)
  """
  def check(%Bot{bot_type: "internal"}), do: {:ok, "healthy"}

  def check(%Bot{bot_type: "external", endpoint_base: nil}), do: {:ok, "unhealthy"}
  def check(%Bot{bot_type: "external", endpoint_base: ""}), do: {:ok, "unhealthy"}

  def check(%Bot{bot_type: "external", endpoint_base: endpoint_base} = bot) do
    Logger.info("Health check stub for external bot #{bot.name} at #{endpoint_base}")
    {:ok, "unknown"}
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
  Returns the game connection URL for a bot, or nil for internal bots.
  """
  def game_url(%Bot{bot_type: "internal"}, _game_id), do: nil

  def game_url(%Bot{endpoint_base: nil}, _game_id), do: nil

  def game_url(%Bot{endpoint_base: endpoint_base}, game_id) do
    "#{String.trim_trailing(endpoint_base, "/")}/game/#{game_id}"
  end
end
