defmodule Mix.Tasks.BotTestServer do
  @moduledoc """
  Starts a test server on port 4040 that simulates an external bot endpoint.

  Provides:
    - GET  /game/health_check  → 200 JSON {"status": "ok"}
    - WS   /game/:game_id      → UBI protocol bridge to Rust engine binary

  Usage:
    mix bot_test_server
  """
  use Mix.Task

  @shortdoc "Start a test external bot server on port 4040"

  @impl true
  def run(args) do
    # Ensure deps are started (needed for Bandit, etc.)
    Mix.Task.run("app.start")

    # Allow overriding engine path via CLI arg: mix bot_test_server /path/to/engine
    if engine_override = List.first(args) do
      current = Application.get_env(:bughouse, :bot_engine) || []

      Application.put_env(
        :bughouse,
        :bot_engine,
        Keyword.put(current, :engine_path, engine_override)
      )
    end

    port = 4040

    IO.puts("""
    \n🤖 Bot Test Server starting on port #{port}
    ───────────────────────────────────────────
    Health check:  GET  http://localhost:#{port}/game/health_check
    WebSocket:     WS   ws://localhost:#{port}/game/:game_id
    Engine binary: #{engine_path()}
    ───────────────────────────────────────────
    Press Ctrl+C to stop.
    """)

    {:ok, _pid} =
      Bandit.start_link(
        plug: BotTestServer.Router,
        port: port,
        scheme: :http
      )

    # Block forever
    Process.sleep(:infinity)
  end

  defp engine_path do
    Application.get_env(:bughouse, :bot_engine)[:engine_path] || "not configured"
  end
end

defmodule BotTestServer.Router do
  use Plug.Router

  plug Plug.Logger, log: :info
  plug :match
  plug :dispatch

  # Health check endpoint
  get "/game/health_check" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok", engine: "bughouse-engine-test"}))
  end

  # WebSocket upgrade for UBI game sessions
  get "/game/:game_id" do
    game_id = conn.path_params["game_id"]

    conn
    |> WebSockAdapter.upgrade(BotTestServer.UbiHandler, %{game_id: game_id}, timeout: 60_000)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end

defmodule BotTestServer.UbiHandler do
  @moduledoc """
  WebSocket handler that bridges UBI protocol to the Rust engine binary.

  Each WebSocket connection spawns an Erlang Port to the engine and
  forwards messages bidirectionally:
    - Client WS text frame → engine stdin
    - Engine stdout line   → client WS text frame
  """
  @behaviour WebSock

  require Logger

  @impl true
  def init(%{game_id: game_id}) do
    engine_path = Application.get_env(:bughouse, :bot_engine)[:engine_path]

    if engine_path && File.exists?(engine_path) do
      port =
        Port.open({:spawn_executable, engine_path}, [
          {:args, ["--game-id", game_id]},
          :binary,
          {:line, 4096},
          :use_stdio,
          :exit_status
        ])

      Logger.info("UBI WS: engine spawned for game #{game_id}")
      {:ok, %{port: port, game_id: game_id, line_buffer: ""}}
    else
      Logger.error("UBI WS: engine binary not found at #{inspect(engine_path)}")
      {:stop, :normal, {1000, "engine binary not found"}}
    end
  end

  # Client sends a WS text frame → forward to engine stdin
  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    line = String.trim(text)
    Logger.debug("UBI WS ← client: #{line}")
    Port.command(state.port, line <> "\n")
    {:ok, state}
  end

  # Engine stdout complete line → send to client as WS text frame
  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    full_line =
      if state.line_buffer != "" do
        state.line_buffer <> String.trim(line)
      else
        String.trim(line)
      end

    Logger.debug("UBI WS → client: #{full_line}")
    {:push, {:text, full_line}, %{state | line_buffer: ""}}
  end

  # Engine stdout partial line → buffer
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:ok, %{state | line_buffer: state.line_buffer <> chunk}}
  end

  # Engine process exited
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.info("UBI WS: engine exited with code #{code} for game #{state.game_id}")
    {:stop, :normal, {1000, "engine exited"}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("UBI WS: connection closed for game #{state.game_id}: #{inspect(reason)}")

    if state[:port] do
      # Try to gracefully shut down the engine
      try do
        Port.command(state.port, "quit\n")

        receive do
          {port, {:exit_status, _}} when port == state.port -> :ok
        after
          500 -> Port.close(state.port)
        end
      rescue
        _ -> :ok
      end
    end

    :ok
  end
end
