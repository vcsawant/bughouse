defmodule Bughouse.TeamComm do
  @moduledoc """
  Team-scoped communication for in-game teammate coordination.

  Maps directly to BUP protocol `teammsg`/`partnermsg` types.
  Human players send messages via the UI, bots send via the engine protocol.
  Both flow through team-scoped PubSub topics so only teammates can see them.

  ## BUP Message Types

    * `need` — Request a specific piece (p, n, b, r, q) with optional urgency
    * `stall` — Ask teammate to avoid captures temporarily
    * `play_fast` — Ask teammate to move quickly
    * `material` — Report material advantage/disadvantage (centipawns, engine-only)
    * `threat` — Communicate danger level (low/medium/high/critical)
  """

  @topic_prefix "game:"

  @valid_types ~w(need stall play_fast material threat)a
  @valid_pieces ~w(p n b r q)
  @valid_threat_levels ~w(low medium high critical)a

  # --- PubSub ---

  @doc """
  Subscribes the calling process to team messages for the given game and team.
  """
  def subscribe(invite_code, team) when team in [:team_1, :team_2] do
    Phoenix.PubSub.subscribe(Bughouse.PubSub, topic(invite_code, team))
  end

  @doc """
  Broadcasts a team message to all subscribers on the given team topic.
  """
  def broadcast(invite_code, team, message) when team in [:team_1, :team_2] do
    Phoenix.PubSub.broadcast(
      Bughouse.PubSub,
      topic(invite_code, team),
      {:team_message, message}
    )
  end

  defp topic(invite_code, :team_1), do: @topic_prefix <> invite_code <> ":team_1"
  defp topic(invite_code, :team_2), do: @topic_prefix <> invite_code <> ":team_2"

  # --- Message Building ---

  @doc """
  Builds a team message map with a unique ID and timestamp.
  """
  def build_message(type, params, from_player_id, from_position)
      when type in @valid_types do
    %{
      id: generate_id(),
      type: type,
      params: params,
      from_player_id: from_player_id,
      from_position: from_position,
      timestamp: System.monotonic_time(:millisecond)
    }
  end

  # --- BUP Serialization (message → partnermsg string) ---

  @doc """
  Serializes a team message to a BUP `partnermsg` command string.

  ## Examples

      iex> msg = TeamComm.build_message(:need, %{piece: "n", urgency: :high}, "p1", :board_1_white)
      iex> TeamComm.to_bup_partnermsg(msg)
      "partnermsg need n urgency high"
  """
  def to_bup_partnermsg(%{type: :need, params: params}) do
    base = "partnermsg need #{params.piece}"
    if params[:urgency], do: base <> " urgency #{params.urgency}", else: base
  end

  def to_bup_partnermsg(%{type: :stall, params: params}) do
    base = "partnermsg stall"
    if params[:duration], do: base <> " duration #{params.duration}", else: base
  end

  def to_bup_partnermsg(%{type: :play_fast, params: params}) do
    base = "partnermsg play_fast"
    if params[:reason], do: base <> " reason #{params.reason}", else: base
  end

  def to_bup_partnermsg(%{type: :material, params: params}) do
    "partnermsg material #{params.value}"
  end

  def to_bup_partnermsg(%{type: :threat, params: params}) do
    "partnermsg threat #{params.level}"
  end

  # --- BUP Parsing (teammsg string → message) ---

  @doc """
  Parses a BUP `teammsg` line from an engine into a structured message.

  ## Examples

      iex> TeamComm.parse_engine_teammsg("teammsg need n urgency high", "bot1", :board_1_white)
      {:ok, %{type: :need, params: %{piece: "n", urgency: :high}, ...}}
  """
  def parse_engine_teammsg("teammsg " <> rest, bot_player_id, bot_position) do
    case parse_teammsg_body(rest) do
      {:ok, type, params} ->
        {:ok, build_message(type, params, bot_player_id, bot_position)}

      :error ->
        {:error, :invalid_teammsg}
    end
  end

  def parse_engine_teammsg(_line, _bot_player_id, _bot_position) do
    {:error, :not_a_teammsg}
  end

  defp parse_teammsg_body("need " <> rest) do
    parts = String.split(rest)

    case parts do
      [piece, "urgency", urgency] when piece in @valid_pieces ->
        case parse_urgency(urgency) do
          {:ok, u} -> {:ok, :need, %{piece: piece, urgency: u}}
          :error -> :error
        end

      [piece] when piece in @valid_pieces ->
        {:ok, :need, %{piece: piece}}

      _ ->
        :error
    end
  end

  defp parse_teammsg_body("stall" <> rest) do
    rest = String.trim(rest)

    cond do
      rest == "" ->
        {:ok, :stall, %{}}

      String.starts_with?(rest, "duration ") ->
        case Integer.parse(String.trim_leading(rest, "duration ")) do
          {n, ""} when n > 0 -> {:ok, :stall, %{duration: n}}
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp parse_teammsg_body("play_fast" <> rest) do
    rest = String.trim(rest)

    cond do
      rest == "" ->
        {:ok, :play_fast, %{}}

      String.starts_with?(rest, "reason ") ->
        reason = String.trim_leading(rest, "reason ")

        if reason in ["time", "pressure"] do
          {:ok, :play_fast, %{reason: String.to_atom(reason)}}
        else
          :error
        end

      true ->
        :error
    end
  end

  defp parse_teammsg_body("material " <> value_str) do
    value_str = String.trim(value_str)

    case Integer.parse(value_str) do
      {n, ""} -> {:ok, :material, %{value: n}}
      _ -> :error
    end
  end

  defp parse_teammsg_body("threat " <> level_str) do
    level_str = String.trim(level_str)

    case parse_threat_level(level_str) do
      {:ok, level} -> {:ok, :threat, %{level: level}}
      :error -> :error
    end
  end

  defp parse_teammsg_body(_), do: :error

  # --- Helpers ---

  defp parse_urgency(str) when str in ["low", "medium", "high"],
    do: {:ok, String.to_atom(str)}

  defp parse_urgency(_), do: :error

  defp parse_threat_level(str) do
    atom = String.to_atom(str)
    if atom in @valid_threat_levels, do: {:ok, atom}, else: :error
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # --- Team Helpers ---

  @doc """
  Determines which team a board position belongs to.

  Team 1: board_1_white + board_2_black
  Team 2: board_1_black + board_2_white
  """
  def team_for_position(position) when position in [:board_1_white, :board_2_black], do: :team_1
  def team_for_position(position) when position in [:board_1_black, :board_2_white], do: :team_2

  @doc """
  Determines the team for a set of positions (e.g. a dual bot).
  """
  def team_for_positions(positions) do
    positions
    |> Enum.map(&team_for_position/1)
    |> Enum.uniq()
    |> case do
      [team] -> team
      _ -> nil
    end
  end
end
