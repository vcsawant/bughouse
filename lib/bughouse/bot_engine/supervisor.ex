defmodule Bughouse.BotEngine.Supervisor do
  @moduledoc """
  DynamicSupervisor for bot engine processes.

  Each bot in an active game gets its own OS process (Erlang Port)
  managed by a BotEngineServer GenServer under this supervisor.
  A configurable concurrency limit prevents runaway resource usage.
  """

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {DynamicSupervisor, :start_link, [[name: __MODULE__, strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @doc """
  Start a bot engine for a game. Returns {:error, :bot_limit_reached}
  if the configured max_concurrent limit would be exceeded.
  """
  def start_engine(game_id, invite_code, bot_player_id, positions, bot_config \\ %{}) do
    if active_count() >= max_concurrent() do
      {:error, :bot_limit_reached}
    else
      DynamicSupervisor.start_child(__MODULE__, {
        Bughouse.BotEngine.Server,
        %{
          game_id: game_id,
          invite_code: invite_code,
          bot_player_id: bot_player_id,
          positions: positions,
          bot_config: bot_config
        }
      })
    end
  end

  @doc "Stop a running bot engine process."
  def stop_engine(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc "Number of currently active bot engine processes."
  def active_count do
    %{active: active} = DynamicSupervisor.count_children(__MODULE__)
    active
  end

  @doc "Number of engine slots available before the limit is reached."
  def available_slots do
    max(0, max_concurrent() - active_count())
  end

  defp max_concurrent do
    Application.get_env(:bughouse, :bot_engine)[:max_concurrent] || 1
  end
end
