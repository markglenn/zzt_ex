defmodule ZztEx.Zzt.AI.RicochetTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Bullet

  @bullet 18
  @ricochet 32

  defp bullet_stat(x, y, dx, dy, p1 \\ 0) do
    %Stat{x: x, y: y, cycle: 1, step_x: dx, step_y: dy, p1: p1}
  end

  test "direct ricochet hit reverses the bullet's step" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0),
        element: @bullet
      )
      |> then(fn g -> %{g | tiles: Map.put(g.tiles, {11, 10}, {@ricochet, 0x0A})} end)

    final = Bullet.tick(game, 1)
    bullet = Enum.at(final.stats, 1)

    # Step reversed and bullet advanced one tile in the new direction.
    assert {bullet.x, bullet.y} == {9, 10}
    assert {bullet.step_x, bullet.step_y} == {-1, 0}
  end

  test "perpendicular ricochet below the path deflects the bullet upward" do
    # Bullet moving east. Wall in front, ricochet on the south side.
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0),
        element: @bullet,
        walls: [{11, 10}]
      )
      |> then(fn g -> %{g | tiles: Map.put(g.tiles, {10, 11}, {@ricochet, 0x0A})} end)

    final = Bullet.tick(game, 1)
    bullet = Enum.at(final.stats, 1)

    # (X + StepY, Y + StepX) = (10, 11) is the CW-side ricochet.
    # Reflection: StepX := -StepY, StepY := -StepX → (0, -1). Bullet
    # moves one step north from (10, 10) to (10, 9).
    assert {bullet.x, bullet.y} == {10, 9}
    assert {bullet.step_x, bullet.step_y} == {0, -1}
  end

  test "wall with no ricochet nearby kills the bullet" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0),
        element: @bullet,
        walls: [{11, 10}]
      )

    final = Bullet.tick(game, 1)
    assert length(final.stats) == 1
  end
end
