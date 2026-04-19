defmodule ZztEx.Zzt.AI.BlinkWallTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Board, Game, Stat}
  alias ZztEx.Zzt.AI.BlinkWall

  @blink_wall 29
  @blink_ray_ew 33
  @blink_ray_ns 43
  @empty 0

  defp blank_tiles do
    for y <- 1..Board.height(), x <- 1..Board.width(), into: %{} do
      {{x, y}, {@empty, 0x0F}}
    end
  end

  defp base_player do
    %{
      health: 100,
      ammo: 0,
      gems: 0,
      keys: List.duplicate(false, 7),
      torches: 0,
      score: 0,
      energizer_ticks: 0
    }
  end

  # Place a blink wall at (wx, wy) firing a beam of `color` along
  # step. Optional `extras` overlay extra tiles. Player sits in a corner
  # out of the way unless overridden.
  defp scene(opts) do
    {wx, wy} = Keyword.fetch!(opts, :wall_xy)
    {sx, sy} = Keyword.fetch!(opts, :step)
    color = Keyword.get(opts, :color, 0x0E)
    p1 = Keyword.get(opts, :p1, 0)
    p2 = Keyword.get(opts, :p2, 2)
    p3 = Keyword.get(opts, :p3, 0)
    extras = Keyword.get(opts, :extras, [])
    {px, py} = Keyword.get(opts, :player_xy, {1, 1})

    wall_stat = %Stat{x: wx, y: wy, cycle: 1, step_x: sx, step_y: sy, p1: p1, p2: p2, p3: p3}

    tiles =
      extras
      |> Enum.reduce(blank_tiles(), fn {pos, tile}, acc -> Map.put(acc, pos, tile) end)
      |> Map.put({wx, wy}, {@blink_wall, color})
      |> Map.put({px, py}, {4, 0x1F})

    %Game{
      tiles: tiles,
      stats: [%Stat{x: px, y: py, cycle: 1}, wall_stat],
      player: base_player(),
      stat_tick: 0
    }
  end

  describe "tick/2" do
    test "fresh wall (P3 = 0) initializes with startup delay" do
      game = scene(wall_xy: {10, 10}, step: {1, 0}, p1: 5)
      final = BlinkWall.tick(game, 1)

      # P3 := P1 + 1 = 6, then (not 1) decrement to 5.
      assert Enum.at(final.stats, 1).p3 == 5
      # No ray yet.
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == @empty
    end

    test "P3 = 2 just decrements" do
      game = scene(wall_xy: {10, 10}, step: {1, 0}, p3: 2)
      final = BlinkWall.tick(game, 1)

      assert Enum.at(final.stats, 1).p3 == 1
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == @empty
    end

    test "P3 = 1 fires an EW ray along the step direction" do
      game = scene(wall_xy: {10, 10}, step: {1, 0}, p3: 1, p2: 3, color: 0x0C)
      final = BlinkWall.tick(game, 1)

      # Beam fills eastward until the board edge.
      for x <- 11..60 do
        {elem, color} = Map.fetch!(final.tiles, {x, 10})
        assert elem == @blink_ray_ew
        assert color == 0x0C
      end

      # Counter reset: P3 = P2 * 2 + 1 = 7.
      assert Enum.at(final.stats, 1).p3 == 7
    end

    test "NS ray uses the vertical glyph" do
      game = scene(wall_xy: {10, 10}, step: {0, 1}, p3: 1, p2: 2)
      final = BlinkWall.tick(game, 1)

      {elem, _} = Map.fetch!(final.tiles, {10, 11})
      assert elem == @blink_ray_ns
    end

    test "existing beam of the wall's color is retracted on the next fire" do
      # Pre-place a ray matching the wall's color to the east.
      extras =
        for x <- 11..15 do
          {{x, 10}, {@blink_ray_ew, 0x0E}}
        end

      game = scene(wall_xy: {10, 10}, step: {1, 0}, p3: 1, p2: 2, color: 0x0E, extras: extras)
      final = BlinkWall.tick(game, 1)

      # Rays cleared back to empty.
      for x <- 11..15 do
        assert Map.fetch!(final.tiles, {x, 10}) |> elem(0) == @empty
      end

      # Retract path only clears the existing ray; doesn't lay a new
      # beam past it.
      assert Map.fetch!(final.tiles, {16, 10}) |> elem(0) == @empty
    end

    test "ray halts against a non-empty, non-destructible wall" do
      extras = [{{14, 10}, {22, 0x0F}}]
      game = scene(wall_xy: {10, 10}, step: {1, 0}, p3: 1, p2: 1, extras: extras)
      final = BlinkWall.tick(game, 1)

      # Ray fills 11..13 and stops.
      for x <- 11..13, do: assert(Map.fetch!(final.tiles, {x, 10}) |> elem(0) == @blink_ray_ew)
      # Wall still there.
      assert Map.fetch!(final.tiles, {14, 10}) |> elem(0) == 22
      # Past the wall, nothing.
      assert Map.fetch!(final.tiles, {15, 10}) |> elem(0) == @empty
    end

    test "player in the ray path gets shoved aside to an empty tile" do
      # Horizontal ray firing east. Player at (12, 10). Empty at (12, 9).
      game = scene(wall_xy: {10, 10}, step: {1, 0}, p3: 1, p2: 1, player_xy: {12, 10})

      final = BlinkWall.tick(game, 1)

      player = Enum.at(final.stats, 0)
      # Player pushed north.
      assert {player.x, player.y} == {12, 9}
      # Reference takes 10 damage first (BoardDamageTile on a destructible
      # tile) even though the player also gets shoved aside.
      assert final.player.health == 90
    end

    test "player with no escape square dies" do
      # Fill the tiles above/below the ray position with walls so the
      # player can't be shoved out of the way.
      extras = [
        {{12, 9}, {22, 0x0F}},
        {{12, 11}, {22, 0x0F}}
      ]

      game =
        scene(
          wall_xy: {10, 10},
          step: {1, 0},
          p3: 1,
          p2: 1,
          player_xy: {12, 10},
          extras: extras
        )

      final = BlinkWall.tick(game, 1)

      assert final.player.health == 0
    end
  end
end
