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
end
