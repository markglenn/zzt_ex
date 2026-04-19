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

  test "hitting a monster whose stat index is lower than the bullet's" do
    # Regression: ordering was `damage_tile` then `remove_stat`, which
    # shifted stat_idx down by one and made `remove_stat(old_idx)` hit
    # the end of the list. Here the lion sits at a lower index than
    # the bullet so the bullet's idx shifts on the monster's removal.
    lion = %Stat{x: 11, y: 10, cycle: 3, p1: 0}

    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0, 0),
        element: @bullet
      )

    # Re-order: player, lion, bullet — bullet now at idx 2, lion at 1.
    [player_stat, bullet_stat] = game.stats
    tiles = Map.put(game.tiles, {11, 10}, {41, 0x0C})
    game = %{game | tiles: tiles, stats: [player_stat, lion, bullet_stat]}

    final = Bullet.tick(game, 2)

    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 0
    assert final.player.score == 1
    # Bullet and lion both gone; only the player remains.
    assert length(final.stats) == 1
  end

  test "dying against an object sends :SHOT which runs inline" do
    code = "@obj\r:SHOT\r#set got_shot\r#end\r"
    obj = %Stat{x: 11, y: 10, cycle: 3, code: code}

    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: bullet_stat(10, 10, 1, 0, 0),
        element: @bullet
      )

    # Object tile at (11, 10) blocks the bullet — bullet dies and
    # :SHOT should run during this very tick.
    game = %{
      game
      | tiles: Map.put(game.tiles, {11, 10}, {36, 0x0F}),
        stats: game.stats ++ [obj]
    }

    final = ZztEx.Zzt.AI.Bullet.tick(game, 1)

    assert ZztEx.Zzt.Game.flag?(final, "got_shot")
    # Bullet is gone, object still there.
    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 36
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
