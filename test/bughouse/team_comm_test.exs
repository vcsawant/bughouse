defmodule Bughouse.TeamCommTest do
  use ExUnit.Case, async: true
  alias Bughouse.TeamComm

  describe "build_message/4" do
    test "builds a need message with piece and urgency" do
      msg =
        TeamComm.build_message(:need, %{piece: "n", urgency: :high}, "player1", :board_1_white)

      assert msg.type == :need
      assert msg.params == %{piece: "n", urgency: :high}
      assert msg.from_player_id == "player1"
      assert msg.from_position == :board_1_white
      assert is_binary(msg.id)
      assert is_integer(msg.timestamp)
    end

    test "builds a stall message" do
      msg = TeamComm.build_message(:stall, %{}, "player1", :board_2_black)

      assert msg.type == :stall
      assert msg.params == %{}
    end

    test "builds a play_fast message" do
      msg = TeamComm.build_message(:play_fast, %{reason: :time}, "player1", :board_1_white)

      assert msg.type == :play_fast
      assert msg.params == %{reason: :time}
    end

    test "builds a material message" do
      msg = TeamComm.build_message(:material, %{value: 350}, "bot1", :board_1_white)

      assert msg.type == :material
      assert msg.params.value == 350
    end

    test "builds a threat message" do
      msg = TeamComm.build_message(:threat, %{level: :critical}, "player1", :board_1_black)

      assert msg.type == :threat
      assert msg.params.level == :critical
    end

    test "generates unique IDs" do
      msg1 = TeamComm.build_message(:stall, %{}, "p1", :board_1_white)
      msg2 = TeamComm.build_message(:stall, %{}, "p1", :board_1_white)

      assert msg1.id != msg2.id
    end
  end

  describe "to_ubi_partnermsg/1" do
    test "serializes need with urgency" do
      msg = TeamComm.build_message(:need, %{piece: "n", urgency: :high}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg need n urgency high"
    end

    test "serializes need without urgency" do
      msg = TeamComm.build_message(:need, %{piece: "q"}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg need q"
    end

    test "serializes stall with duration" do
      msg = TeamComm.build_message(:stall, %{duration: 2}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg stall duration 2"
    end

    test "serializes stall without duration" do
      msg = TeamComm.build_message(:stall, %{}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg stall"
    end

    test "serializes play_fast with reason" do
      msg = TeamComm.build_message(:play_fast, %{reason: :time}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg play_fast reason time"
    end

    test "serializes play_fast without reason" do
      msg = TeamComm.build_message(:play_fast, %{}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg play_fast"
    end

    test "serializes material" do
      msg = TeamComm.build_message(:material, %{value: 350}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg material 350"
    end

    test "serializes negative material" do
      msg = TeamComm.build_message(:material, %{value: -150}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg material -150"
    end

    test "serializes threat" do
      msg = TeamComm.build_message(:threat, %{level: :critical}, "p1", :board_1_white)
      assert TeamComm.to_ubi_partnermsg(msg) == "partnermsg threat critical"
    end
  end

  describe "parse_engine_teammsg/3" do
    test "parses need with urgency" do
      assert {:ok, msg} =
               TeamComm.parse_engine_teammsg(
                 "teammsg need n urgency high",
                 "bot1",
                 :board_1_white
               )

      assert msg.type == :need
      assert msg.params == %{piece: "n", urgency: :high}
      assert msg.from_player_id == "bot1"
      assert msg.from_position == :board_1_white
    end

    test "parses need without urgency" do
      assert {:ok, msg} =
               TeamComm.parse_engine_teammsg("teammsg need q", "bot1", :board_1_white)

      assert msg.type == :need
      assert msg.params == %{piece: "q"}
    end

    test "parses stall with duration" do
      assert {:ok, msg} =
               TeamComm.parse_engine_teammsg("teammsg stall duration 2", "bot1", :board_1_white)

      assert msg.type == :stall
      assert msg.params == %{duration: 2}
    end

    test "parses stall without duration" do
      assert {:ok, msg} =
               TeamComm.parse_engine_teammsg("teammsg stall", "bot1", :board_1_white)

      assert msg.type == :stall
      assert msg.params == %{}
    end

    test "parses play_fast with reason" do
      assert {:ok, msg} =
               TeamComm.parse_engine_teammsg(
                 "teammsg play_fast reason time",
                 "bot1",
                 :board_1_white
               )

      assert msg.type == :play_fast
      assert msg.params == %{reason: :time}
    end

    test "parses play_fast without reason" do
      assert {:ok, msg} =
               TeamComm.parse_engine_teammsg("teammsg play_fast", "bot1", :board_1_white)

      assert msg.type == :play_fast
      assert msg.params == %{}
    end

    test "parses material positive" do
      assert {:ok, msg} =
               TeamComm.parse_engine_teammsg("teammsg material +350", "bot1", :board_1_white)

      assert msg.type == :material
      assert msg.params == %{value: 350}
    end

    test "parses material negative" do
      assert {:ok, msg} =
               TeamComm.parse_engine_teammsg("teammsg material -150", "bot1", :board_1_white)

      assert msg.type == :material
      assert msg.params == %{value: -150}
    end

    test "parses threat levels" do
      for level <- ~w(low medium high critical) do
        assert {:ok, msg} =
                 TeamComm.parse_engine_teammsg(
                   "teammsg threat #{level}",
                   "bot1",
                   :board_1_white
                 )

        assert msg.type == :threat
        assert msg.params == %{level: String.to_atom(level)}
      end
    end

    test "rejects invalid piece in need" do
      assert {:error, :invalid_teammsg} =
               TeamComm.parse_engine_teammsg("teammsg need x", "bot1", :board_1_white)
    end

    test "rejects invalid urgency" do
      assert {:error, :invalid_teammsg} =
               TeamComm.parse_engine_teammsg(
                 "teammsg need n urgency extreme",
                 "bot1",
                 :board_1_white
               )
    end

    test "rejects non-teammsg lines" do
      assert {:error, :not_a_teammsg} =
               TeamComm.parse_engine_teammsg("bestmove board A e2e4", "bot1", :board_1_white)
    end

    test "rejects unknown message types" do
      assert {:error, :invalid_teammsg} =
               TeamComm.parse_engine_teammsg("teammsg unknown stuff", "bot1", :board_1_white)
    end
  end

  describe "team_for_position/1" do
    test "team 1 positions" do
      assert TeamComm.team_for_position(:board_1_white) == :team_1
      assert TeamComm.team_for_position(:board_2_black) == :team_1
    end

    test "team 2 positions" do
      assert TeamComm.team_for_position(:board_1_black) == :team_2
      assert TeamComm.team_for_position(:board_2_white) == :team_2
    end
  end

  describe "team_for_positions/1" do
    test "single team" do
      assert TeamComm.team_for_positions([:board_1_white]) == :team_1
      assert TeamComm.team_for_positions([:board_1_black, :board_2_white]) == :team_2
    end

    test "mixed teams returns nil" do
      assert TeamComm.team_for_positions([:board_1_white, :board_1_black]) == nil
    end
  end

  describe "PubSub isolation" do
    test "team_1 messages only reach team_1 subscribers" do
      invite_code = "test_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"

      # Subscribe to team_1
      TeamComm.subscribe(invite_code, :team_1)

      # Broadcast to team_1
      msg = TeamComm.build_message(:stall, %{}, "p1", :board_1_white)
      TeamComm.broadcast(invite_code, :team_1, msg)

      assert_receive {:team_message, received}
      assert received.id == msg.id
    end

    test "team_2 messages do not reach team_1 subscribers" do
      invite_code = "test_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"

      # Subscribe to team_1
      TeamComm.subscribe(invite_code, :team_1)

      # Broadcast to team_2
      msg = TeamComm.build_message(:stall, %{}, "p3", :board_1_black)
      TeamComm.broadcast(invite_code, :team_2, msg)

      refute_receive {:team_message, _}, 100
    end
  end
end
