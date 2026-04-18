defmodule ZztEx.Zzt.AI.SlimeTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Slime

  @slime 37
  @breakable 23

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  defp slime_stat(x, y, p2), do: %Stat{x: x, y: y, cycle: 1, p1: 0, p2: p2}

  test "slime increments p1 until it reaches p2 before spreading" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: slime_stat(10, 10, 3),
        element: @slime
      )

    # First three ticks only bump p1; spread doesn't happen yet.
    final =
      Enum.reduce(1..3, game, fn _, acc ->
        result = Slime.tick(acc, 1)
        slime = Enum.at(result.stats, 1)
        assert {slime.x, slime.y} == {10, 10}
        result
      end)

    assert Enum.at(final.stats, 1).p1 == 3
  end

  test "slime leaves a breakable trail when it spreads" do
    # p2 = 0 so every tick is a spread attempt.
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: slime_stat(10, 10, 0),
        element: @slime
      )

    final = Slime.tick(game, 1)
    slime = Enum.at(final.stats, 1)

    # Slime actually moved somewhere adjacent.
    refute {slime.x, slime.y} == {10, 10}
    # And it left breakable behind at its start.
    {element, _color} = Map.fetch!(final.tiles, {10, 10})
    assert element == @breakable
  end

  test "slime boxed in by walls on all sides doesn't move" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: slime_stat(10, 10, 0),
        element: @slime,
        walls: [{9, 10}, {11, 10}, {10, 9}, {10, 11}]
      )

    final = Enum.reduce(1..10, game, fn _, acc -> Slime.tick(acc, 1) end)
    slime = Enum.at(final.stats, 1)

    assert {slime.x, slime.y} == {10, 10}
  end
end
