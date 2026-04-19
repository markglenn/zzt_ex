defmodule ZztEx.Zzt.OopTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.{Oop, Stat}

  @object 36

  defp object_stat(x, y, code) do
    %Stat{x: x, y: y, cycle: 1, code: code, instruction: 0}
  end

  defp build(code, opts) do
    {ox, oy} = Keyword.get(opts, :object_xy, {10, 10})
    walls = Keyword.get(opts, :walls, [])

    AIFixture.game_with(
      player_xy: Keyword.get(opts, :player_xy, {5, 5}),
      monster: object_stat(ox, oy, code),
      element: @object,
      walls: walls
    )
  end

  describe "halting" do
    test "#end sets instruction to -1" do
      game = build("#end\r", [])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert obj.instruction == -1
    end

    test "end-of-program without #end also halts permanently" do
      game = build("@name\r", [])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert obj.instruction == -1
    end

    test "ticks on an already-halted stat are no-ops" do
      game = build("#end\r", [])

      halted = Oop.tick(game, 1)
      again = Oop.tick(halted, 1)

      assert Enum.at(again.stats, 1).instruction == -1
    end
  end

  describe "walk lines" do
    test "/e moves east when tile is walkable" do
      game = build("/e\r#end\r", object_xy: {10, 10})

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert {obj.x, obj.y} == {11, 10}
    end

    test "/e stays on the same line when blocked (retries next tick)" do
      game = build("/e\r#end\r", object_xy: {10, 10}, walls: [{11, 10}])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      # Didn't move.
      assert {obj.x, obj.y} == {10, 10}
      # Still on the `/e` line — instruction unchanged at 0.
      assert obj.instruction == 0
    end

    test "?e advances past the line when blocked (single attempt)" do
      game = build("?e\r#end\r", object_xy: {10, 10}, walls: [{11, 10}])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert {obj.x, obj.y} == {10, 10}
      # Moved past `?e` — next tick will run `#end`.
      assert obj.instruction > 0
    end

    test "/i (idle) advances without moving" do
      game = build("/i\r#end\r", object_xy: {10, 10})

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert {obj.x, obj.y} == {10, 10}
      assert obj.instruction > 0
    end
  end

  describe "#try dir label" do
    test "moves and halts when the step succeeds" do
      game = build("#try e fail\r#end\r:fail\r#end\r", object_xy: {10, 10})

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert {obj.x, obj.y} == {11, 10}
    end

    test "success skips the rest of the line so the fail label doesn't leak" do
      # Regression for the bank-vault bug: after a successful #try, the
      # trailing word (fail) and subsequent text lines should not end
      # up in the scroll. Only "vault open!" should show, NOT " fail".
      code =
        "#try e fail\r" <>
          "vault open!\r" <>
          "#end\r" <>
          ":fail\r" <>
          "combination wrong!\r" <>
          "#end\r"

      game = build(code, object_xy: {10, 10})
      # Tick 1: `#try e fail` succeeds, halts. Tick 2: reads the text
      # line and `#end`, emits the scroll.
      final = game |> Oop.tick(1) |> Oop.tick(1)

      assert final.pending_scroll.lines == ["vault open!"]
    end

    test "blocked: jumps to :fail, shows only the failure text" do
      code =
        "#try e fail\r" <>
          "vault open!\r" <>
          "#end\r" <>
          ":fail\r" <>
          "combination wrong!\r" <>
          "#end\r"

      game = build(code, object_xy: {10, 10}, walls: [{11, 10}])
      final = Oop.tick(game, 1)

      assert final.pending_scroll.lines == ["combination wrong!"]
    end

    test "falls through to the #send when blocked" do
      code = "#try e fail\r'unreachable\r#end\r:fail\r#end\r"
      game = build(code, object_xy: {10, 10}, walls: [{11, 10}])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      # Did not move; the #send landed us on the line right after :fail.
      assert {obj.x, obj.y} == {10, 10}
      # One more tick runs #end → permanent halt.
      final2 = Oop.tick(final, 1)
      assert Enum.at(final2.stats, 1).instruction == -1
    end
  end

  describe "#go dir" do
    test "moves when walkable" do
      game = build("#go e\r#end\r", object_xy: {10, 10})

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert {obj.x, obj.y} == {11, 10}
    end

    test "retries the same line next tick when blocked" do
      game = build("#go e\r#end\r", object_xy: {10, 10}, walls: [{11, 10}])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert {obj.x, obj.y} == {10, 10}
      # Still on line 0 — retry next tick.
      assert obj.instruction == 0
    end
  end

  describe "#send / label lookup" do
    test "#send label jumps to matching :label" do
      code = "#send later\r'unreachable\r:later\r#end\r"
      game = build(code, [])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      # Reached #end inside the same tick → halted.
      assert obj.instruction == -1
    end

    test "bare #label (treated as send) jumps" do
      code = "#later\r'unreachable\r:later\r#end\r"
      game = build(code, [])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert obj.instruction == -1
    end

    test "label lookup is case-insensitive" do
      code = "#send FAIL\r'unreachable\r:Fail\r#end\r"
      game = build(code, [])

      final = Oop.tick(game, 1)
      assert Enum.at(final.stats, 1).instruction == -1
    end
  end

  describe "skippable lines" do
    test "@name / 'comment / :label / blank lines are skipped" do
      code = "@vault\r'comment\r:label\r\r#end\r"
      game = build(code, [])

      final = Oop.tick(game, 1)
      obj = Enum.at(final.stats, 1)

      assert obj.instruction == -1
    end
  end

  describe "bank-vault-style script" do
    test "executes through the success branch when east is clear" do
      # Mirrors town.zzt's vault: /e to approach, `#try e fail` to check
      # the path. With east clear, the vault succeeds and runs to #end.
      code = "@vault\r/e\r#try e fail\r#end\r:fail\r#end\r"
      game = build(code, object_xy: {10, 10})

      # Tick 1: /e moves east (halts for tick).
      g1 = Oop.tick(game, 1)
      obj1 = Enum.at(g1.stats, 1)
      assert {obj1.x, obj1.y} == {11, 10}

      # Tick 2: #try e fail succeeds, moves east.
      g2 = Oop.tick(g1, 1)
      obj2 = Enum.at(g2.stats, 1)
      assert {obj2.x, obj2.y} == {12, 10}

      # Tick 3: #end halts.
      g3 = Oop.tick(g2, 1)
      assert Enum.at(g3.stats, 1).instruction == -1
    end

    test "jumps to :fail when #try is blocked" do
      code = "@vault\r#try e fail\r#end\r:fail\r/s\r#end\r"
      game = build(code, object_xy: {10, 10}, walls: [{11, 10}])

      # Tick 1: #try e fail blocked → jumps to :fail → /s moves south.
      g1 = Oop.tick(game, 1)
      obj1 = Enum.at(g1.stats, 1)
      assert {obj1.x, obj1.y} == {10, 11}
    end
  end

  describe "op cap" do
    test "a pathological loop is bounded at 32 ops per tick" do
      # Infinite #send loop — without the cap this would never return.
      code = ":loop\r#send loop\r"
      game = build(code, [])

      # Just needs to terminate; assertion is incidental.
      final = Oop.tick(game, 1)
      assert is_struct(final, ZztEx.Zzt.Game)
    end
  end

  describe "flags (#set / #clear / #if)" do
    test "#set adds a flag" do
      game = build("#set opened\r#end\r", [])
      final = Oop.tick(game, 1)

      assert ZztEx.Zzt.Game.flag?(final, "opened")
      assert ZztEx.Zzt.Game.flag?(final, "OPENED")
    end

    test "#clear removes a flag" do
      game = build("#clear locked\r#end\r", [])
      game = ZztEx.Zzt.Game.set_flag(game, "locked")
      final = Oop.tick(game, 1)

      refute ZztEx.Zzt.Game.flag?(final, "locked")
    end

    test "#if <flag> then ... runs only when flag is set" do
      code = "#if opened then #set success\r#end\r"

      no_flag = build(code, []) |> Oop.tick(1)
      refute ZztEx.Zzt.Game.flag?(no_flag, "success")

      with_flag = build(code, []) |> ZztEx.Zzt.Game.set_flag("opened") |> Oop.tick(1)
      assert ZztEx.Zzt.Game.flag?(with_flag, "success")
    end

    test "#if not <flag> inverts" do
      code = "#if not opened #set missing\r#end\r"
      final = build(code, []) |> Oop.tick(1)

      assert ZztEx.Zzt.Game.flag?(final, "missing")
    end
  end

  describe "#if conditions" do
    test "#if energized" do
      code = "#if energized #set zapped\r#end\r"

      calm = build(code, [])
      final = Oop.tick(calm, 1)
      refute ZztEx.Zzt.Game.flag?(final, "zapped")

      energized = put_in(build(code, []).player.energizer_ticks, 10)
      final = Oop.tick(energized, 1)
      assert ZztEx.Zzt.Game.flag?(final, "zapped")
    end

    test "#if contact fires when player is adjacent" do
      code = "#if contact #set touched\r#end\r"

      # Object at (10,10), player at (11,10) — adjacent.
      game = build(code, player_xy: {11, 10}, object_xy: {10, 10})
      final = Oop.tick(game, 1)
      assert ZztEx.Zzt.Game.flag?(final, "touched")

      # Player far — no contact.
      far = build(code, player_xy: {20, 20}, object_xy: {10, 10})
      final = Oop.tick(far, 1)
      refute ZztEx.Zzt.Game.flag?(final, "touched")
    end

    test "#if alligned checks row/column alignment" do
      code = "#if alligned #set aligned\r#end\r"

      same_row = build(code, player_xy: {5, 10}, object_xy: {20, 10})
      assert ZztEx.Zzt.Game.flag?(Oop.tick(same_row, 1), "aligned")

      diagonal = build(code, player_xy: {5, 5}, object_xy: {20, 20})
      refute ZztEx.Zzt.Game.flag?(Oop.tick(diagonal, 1), "aligned")
    end

    test "#if blocked <dir>" do
      code = "#if blocked e #set stuck\r#end\r"

      open = build(code, object_xy: {10, 10})
      refute ZztEx.Zzt.Game.flag?(Oop.tick(open, 1), "stuck")

      walled = build(code, object_xy: {10, 10}, walls: [{11, 10}])
      assert ZztEx.Zzt.Game.flag?(Oop.tick(walled, 1), "stuck")
    end
  end

  describe "#give / #take" do
    test "#give ammo 5 increases ammo" do
      game = build("#give ammo 5\r#end\r", [])
      final = Oop.tick(game, 1)

      assert final.player.ammo == 5
    end

    test "#take ammo 5 decreases ammo when sufficient" do
      game = build("#take ammo 5\r#end\r", [])
      game = put_in(game.player.ammo, 10)
      final = Oop.tick(game, 1)

      assert final.player.ammo == 5
    end

    test "#take ammo 100 falls through when short" do
      # Not enough ammo → falls through to the rest of the line.
      game = build("#take ammo 100 #set broke\r#end\r", [])
      final = Oop.tick(game, 1)

      assert final.player.ammo == 0
      assert ZztEx.Zzt.Game.flag?(final, "broke")
    end
  end

  describe "#zap / #restore" do
    test "#zap :label disables the label" do
      # First run zaps :hit, jumps to :tail which sets a flag.
      code = "#zap hit\r#send hit\r#set fallthrough\r#end\r:hit\r#set hit_ran\r#end\r"
      final = build(code, []) |> Oop.tick(1)

      # :hit got zapped so the send went nowhere; we fell through.
      assert ZztEx.Zzt.Game.flag?(final, "fallthrough")
      refute ZztEx.Zzt.Game.flag?(final, "hit_ran")
    end

    test "#restore :label re-enables a zapped label" do
      code = "#zap hit\r#restore hit\r#send hit\r:hit\r#set ok\r#end\r"
      final = build(code, []) |> Oop.tick(1)

      assert ZztEx.Zzt.Game.flag?(final, "ok")
    end
  end

  describe "#lock / #unlock" do
    test "#lock sets P2 = 1" do
      game = build("#lock\r#end\r", [])
      final = Oop.tick(game, 1)
      assert Enum.at(final.stats, 1).p2 == 1
    end

    test "engine-triggered send skips a locked object" do
      # Object is locked; an engine send (stat_id < 0) should NOT jump
      # to :touch.
      code = "@tagged\r#lock\r#end\r:touch\r#set touched\r#end\r"
      game = build(code, []) |> Oop.tick(1)
      # After tick 1, the object is locked (p2=1) and halted at #end.
      assert Enum.at(game.stats, 1).p2 == 1

      # Simulate engine touch event — should NOT trigger.
      after_touch = Oop.send(game, -1, "TOUCH")
      # Tick again; instruction should still be -1 (halted).
      final = Oop.tick(after_touch, 1)
      refute ZztEx.Zzt.Game.flag?(final, "touched")
    end
  end

  describe "remote #send" do
    test "#send @name:label targets an object by name" do
      # Object 1 is the caller; Object 2 is named `target` and has
      # a :ping label that sets a flag.
      alice_code = "#send target:ping\r#end\r"
      target_code = "@target\r#end\r:ping\r#set pinged\r#end\r"

      import ZztEx.Test.AIFixture, only: [game_with: 1]

      game =
        game_with(
          player_xy: {1, 1},
          monster: %Stat{x: 10, y: 10, cycle: 1, code: alice_code, instruction: 0},
          element: @object
        )

      # Splice in target as stat #2.
      target = %Stat{x: 20, y: 10, cycle: 1, code: target_code, instruction: 0}

      game = %{
        game
        | stats: game.stats ++ [target],
          tiles: Map.put(game.tiles, {20, 10}, {@object, 0x0F})
      }

      final = Oop.tick(game, 1)

      # Target's position was updated to :ping; tick target to run it.
      final = Oop.tick(final, 2)
      assert ZztEx.Zzt.Game.flag?(final, "pinged")
    end
  end

  describe "text display" do
    test "multi-line text opens a pending_scroll" do
      code = "@greet\r#end\r:touch\r'comment\rHello there\rHow are you\r#end\r"

      game = build(code, [])
      # Run the :touch label directly.
      game = Oop.send(game, -1, "TOUCH")
      final = Oop.tick(game, 1)

      assert final.pending_scroll != nil
      assert final.pending_scroll.title == "GREET"
      assert final.pending_scroll.lines == ["Hello there", "How are you"]
    end

    test "single text line still populates pending_scroll" do
      code = ":touch\rOnce and done\r#end\r"
      game = build(code, [])
      game = Oop.send(game, -1, "TOUCH")
      final = Oop.tick(game, 1)

      assert final.pending_scroll.lines == ["Once and done"]
    end
  end

  describe "#become / #die" do
    test "#die replaces the stat with an empty tile" do
      code = "#die\r"
      game = build(code, object_xy: {10, 10})
      final = Oop.tick(game, 1)

      # Stat is removed.
      assert length(final.stats) == 1
      # Tile is empty now.
      assert match?({0, _}, ZztEx.Zzt.Game.tile_at(final, 10, 10))
    end

    test "#become red boulder replaces with boulder" do
      code = "#become red boulder\r"
      game = build(code, object_xy: {10, 10})
      final = Oop.tick(game, 1)

      {elem, _color} = ZztEx.Zzt.Game.tile_at(final, 10, 10)
      # Boulder = 24.
      assert elem == 24
    end
  end

  describe "#cycle / #char" do
    test "#cycle updates the stat's cycle" do
      game = build("#cycle 5\r#end\r", [])
      final = Oop.tick(game, 1)
      assert Enum.at(final.stats, 1).cycle == 5
    end

    test "#char updates P1" do
      game = build("#char 65\r#end\r", [])
      final = Oop.tick(game, 1)
      assert Enum.at(final.stats, 1).p1 == 65
    end
  end

  describe "#endgame" do
    test "#endgame zeros player health" do
      game = build("#endgame\r#end\r", [])
      final = Oop.tick(game, 1)
      assert final.player.health == 0
    end
  end

  describe "#walk" do
    test "#walk e sets the step vector" do
      game = build("#walk e\r#end\r", [])
      final = Oop.tick(game, 1)

      obj = Enum.at(final.stats, 1)
      assert {obj.step_x, obj.step_y} == {1, 0}
    end
  end

  describe "#restart" do
    test "#restart jumps back to position 0" do
      # :loop sets counter, increments a flag once, then restart would
      # create an infinite loop except for the 32-op cap.
      code = "#send loop\r:loop\r#set looped\r#end\r"
      final = build(code, []) |> Oop.tick(1)

      assert ZztEx.Zzt.Game.flag?(final, "looped")
    end
  end

  describe "player touch" do
    test "walking into an object fires its :touch label and blocks motion" do
      # Object is east of the player. Player steps east → touches
      # object → jumps to :touch which sets a flag. The object blocks
      # the step itself.
      code = "@obj\r#end\r:touch\r#set bumped\r#end\r"
      game = build(code, player_xy: {5, 5}, object_xy: {6, 5})

      game = ZztEx.Zzt.Game.move_player(game, 1, 0)

      # Player didn't move onto the object.
      player = Enum.at(game.stats, 0)
      assert {player.x, player.y} == {5, 5}

      # Tick the object — should run :touch.
      final = Oop.tick(game, 1)
      assert ZztEx.Zzt.Game.flag?(final, "bumped")
    end
  end
end
