defmodule ZztEx.Zzt.AI.RuffianTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Ruffian

  @ruffian 35

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  defp ruffian_stat(x, y, opts) do
    %Stat{
      x: x,
      y: y,
      cycle: 1,
      p1: Keyword.get(opts, :p1, 0),
      p2: Keyword.get(opts, :p2, 0),
      step_x: Keyword.get(opts, :step_x, 0),
      step_y: Keyword.get(opts, :step_y, 0)
    }
  end

  test "resting ruffian with low restfulness starts walking within a few ticks" do
    game =
      AIFixture.game_with(
        player_xy: {30, 20},
        monster: ruffian_stat(5, 5, p2: 0),
        element: @ruffian
      )

    final =
      AIFixture.tick_until(game, &Ruffian.tick(&1, 1), fn g ->
        r = Enum.at(g.stats, 1)
        r && (r.step_x != 0 or r.step_y != 0 or {r.x, r.y} != {5, 5})
      end)

    ruffian = Enum.at(final.stats, 1)
    assert ruffian.step_x != 0 or ruffian.step_y != 0 or {ruffian.x, ruffian.y} != {5, 5}
  end

  test "walking ruffian stops when blocked" do
    # Facing east into a wall, ruffian should stop instead of phasing through.
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: ruffian_stat(5, 5, step_x: 1),
        element: @ruffian,
        walls: [{6, 5}]
      )

    final = Ruffian.tick(game, 1)
    ruffian = Enum.at(final.stats, 1)

    assert {ruffian.x, ruffian.y} == {5, 5}
    assert {ruffian.step_x, ruffian.step_y} == {0, 0}
  end

  test "aligned ruffian with high p1 redirects toward the player" do
    # Player at (20, 5), ruffian at (10, 5) currently walking west — with
    # p1 = 9 it almost always rotates to chase instead.
    game =
      AIFixture.game_with(
        player_xy: {20, 5},
        monster: ruffian_stat(10, 5, p1: 9, step_x: -1),
        element: @ruffian
      )

    final =
      AIFixture.tick_until(game, &Ruffian.tick(&1, 1), fn g ->
        r = Enum.at(g.stats, 1)
        r && r.x > 10
      end)

    ruffian = Enum.at(final.stats, 1)
    assert ruffian.x > 10
  end
end
