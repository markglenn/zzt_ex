defmodule ZztEx.Zzt.AI.BearTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Bear

  @bear 34

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  defp bear_stat(x, y, p1), do: %Stat{x: x, y: y, cycle: 3, p1: p1}

  test "bear within p1 range closes on the player" do
    # Player at (10, 10), bear at (14, 10) with P1=8 (wide sensitivity).
    game =
      AIFixture.game_with(
        player_xy: {10, 10},
        monster: bear_stat(14, 10, 8),
        element: @bear
      )

    final =
      AIFixture.tick_until(game, &Bear.tick(&1, 1), fn g ->
        length(g.stats) < 2 or Enum.at(g.stats, 1).x < 14
      end)

    case Enum.at(final.stats, 1) do
      nil -> :ok
      bear -> assert bear.x < 14
    end
  end

  test "bear outside p1 range sits still" do
    # Player at (5, 5), bear at (20, 20) with P1=1 — both axes out of range.
    game =
      AIFixture.game_with(
        player_xy: {5, 5},
        monster: bear_stat(20, 20, 1),
        element: @bear
      )

    final = Enum.reduce(1..30, game, fn _, acc -> Bear.tick(acc, 1) end)
    bear = Enum.at(final.stats, 1)

    assert {bear.x, bear.y} == {20, 20}
  end

  test "bear attacking a breakable wall dies with the wall" do
    # Bears are kamikaze in stock ZZT — attacking anything (player or
    # breakable) kills them. Bear east of a breakable, which is east of
    # the player; one tick points west and both tile and bear are gone.
    game =
      AIFixture.game_with(
        player_xy: {5, 10},
        monster: bear_stat(7, 10, 8),
        element: @bear,
        breakables: [{6, 10}]
      )

    final = Bear.tick(game, 1)

    # Breakable destroyed.
    assert Map.fetch!(final.tiles, {6, 10}) |> elem(0) == 0
    # Bear stat removed.
    assert length(final.stats) == 1
  end

  test "bear dies on contact with an energized player" do
    game =
      AIFixture.game_with(
        player_xy: {10, 10},
        monster: bear_stat(11, 10, 8),
        element: @bear,
        energizer: 100
      )

    final = AIFixture.tick_until(game, &Bear.tick(&1, 1), &(length(&1.stats) < 2))

    assert length(final.stats) == 1
    assert final.player.health == 100
  end
end
