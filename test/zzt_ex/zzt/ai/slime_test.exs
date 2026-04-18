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

  test "slime boxed in on all sides dies and leaves a breakable tile" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: slime_stat(10, 10, 0),
        element: @slime,
        walls: [{9, 10}, {11, 10}, {10, 9}, {10, 11}]
      )

    final = Slime.tick(game, 1)

    # Slime stat is gone; tile where it was is now a breakable wall.
    assert length(final.stats) == 1
    assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == @breakable
  end

  test "slime fills every walkable neighbor, splitting into new slimes" do
    # Open floor on all four sides — one direction becomes the move
    # target, the other three spawn replicated slime stats.
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: slime_stat(10, 10, 0),
        element: @slime
      )

    final = Slime.tick(game, 1)

    # Starting: player + 1 slime = 2 stats. After: one moved, three spawned = 4 slimes.
    assert length(final.stats) == 5

    # All four neighbors now hold slime: the first walkable in N/S/W/E
    # order (north) is the moved slime, the other three are replicas.
    slime_positions =
      [{9, 10}, {11, 10}, {10, 9}, {10, 11}]
      |> Enum.count(fn {x, y} ->
        case Map.fetch!(final.tiles, {x, y}) do
          {37, _} -> true
          _ -> false
        end
      end)

    assert slime_positions == 4
    # The original tile was vacated (turned into breakable trail).
    assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == @breakable
  end
end
