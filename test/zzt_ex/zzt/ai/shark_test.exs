defmodule ZztEx.Zzt.AI.SharkTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Shark

  @shark 38

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  defp shark_stat(x, y, p1), do: %Stat{x: x, y: y, cycle: 3, p1: p1}

  test "shark swims on water tiles" do
    # Surround the shark with water so any direction is a valid move.
    game =
      AIFixture.game_with(
        player_xy: {40, 20},
        monster: shark_stat(10, 10, 0),
        element: @shark,
        water: [{9, 10}, {11, 10}, {10, 9}, {10, 11}]
      )

    final =
      AIFixture.tick_until(game, &Shark.tick(&1, 1), fn g ->
        s = Enum.at(g.stats, 1)
        s && {s.x, s.y} != {10, 10}
      end)

    shark = Enum.at(final.stats, 1)
    refute {shark.x, shark.y} == {10, 10}
  end

  test "shark is blocked by non-water tiles" do
    # No water around — shark can't move onto empty tiles either.
    game =
      AIFixture.game_with(
        player_xy: {40, 20},
        monster: shark_stat(10, 10, 0),
        element: @shark
      )

    final = Enum.reduce(1..20, game, fn _, acc -> Shark.tick(acc, 1) end)
    shark = Enum.at(final.stats, 1)

    assert {shark.x, shark.y} == {10, 10}
  end

  test "shark attacks the player on contact" do
    # Shark adjacent to player, surrounded by walls so it can only move
    # east into the player's tile.
    game =
      AIFixture.game_with(
        player_xy: {11, 10},
        monster: shark_stat(10, 10, 0),
        element: @shark,
        walls: [{9, 10}, {10, 9}, {10, 11}]
      )

    final = AIFixture.tick_until(game, &Shark.tick(&1, 1), &(length(&1.stats) < 2))

    assert length(final.stats) == 1
    assert final.player.health == 90
  end
end
