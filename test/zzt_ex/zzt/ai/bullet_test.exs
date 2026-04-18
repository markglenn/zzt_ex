defmodule ZztEx.Zzt.AI.BulletTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Bullet

  @bullet 18

  defp bullet_stat(x, y, dx, dy, p1 \\ 0) do
    %Stat{x: x, y: y, cycle: 1, step_x: dx, step_y: dy, p1: p1}
  end

  test "moves one tile along its step when the way is clear" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0),
        element: @bullet
      )

    final = Bullet.tick(game, 1)
    bullet = Enum.at(final.stats, 1)

    assert {bullet.x, bullet.y} == {11, 10}
  end

  test "dies on impact with a wall (non-destructible)" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0),
        element: @bullet,
        walls: [{11, 10}]
      )

    final = Bullet.tick(game, 1)

    # Stat removed.
    assert length(final.stats) == 1
    # Wall still there, bullet is gone.
    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 22
  end

  test "player bullet kills a lion and scores its bounty" do
    lion = %Stat{x: 11, y: 10, cycle: 3, p1: 0}

    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0, 0),
        element: @bullet
      )
      |> then(fn g ->
        tiles = Map.put(g.tiles, {11, 10}, {41, 0x0C})
        %{g | tiles: tiles, stats: g.stats ++ [lion]}
      end)

    final = Bullet.tick(game, 1)

    # Lion destroyed, bullet removed.
    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 0
    # Lion is worth 1 point.
    assert final.player.score == 1
  end

  test "enemy bullet phases through other monsters (no friendly fire)" do
    lion = %Stat{x: 11, y: 10, cycle: 3, p1: 0}

    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0, 1),
        element: @bullet
      )
      |> then(fn g ->
        tiles = Map.put(g.tiles, {11, 10}, {41, 0x0C})
        %{g | tiles: tiles, stats: g.stats ++ [lion]}
      end)

    final = Bullet.tick(game, 1)

    # Lion not a valid target for enemy bullet → bullet just dies on impact.
    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 41
    assert final.player.score == 0
    # Bullet stat removed, lion still present.
    assert length(final.stats) == 2
  end

  test "enemy bullet kills the player" do
    game =
      AIFixture.game_with(
        player_xy: {11, 10},
        monster: bullet_stat(10, 10, 1, 0, 1),
        element: @bullet,
        walls: []
      )

    final = Bullet.tick(game, 1)

    assert final.player.health == 90
  end

  test "breakable walls are destroyed regardless of source" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0, 1),
        element: @bullet,
        breakables: [{11, 10}]
      )

    final = Bullet.tick(game, 1)

    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 0
  end
end
