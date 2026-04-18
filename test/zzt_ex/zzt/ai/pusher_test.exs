defmodule ZztEx.Zzt.AI.PusherTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Pusher

  @pusher 40

  defp pusher_stat(x, y, step_x, step_y) do
    %Stat{x: x, y: y, cycle: 4, step_x: step_x, step_y: step_y}
  end

  test "pusher advances in its step direction when the way is clear" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: pusher_stat(10, 10, 1, 0),
        element: @pusher
      )

    final = Pusher.tick(game, 1)
    pusher = Enum.at(final.stats, 1)

    assert {pusher.x, pusher.y} == {11, 10}
  end

  test "pusher stays put when blocked" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: pusher_stat(10, 10, 1, 0),
        element: @pusher,
        walls: [{11, 10}]
      )

    final = Pusher.tick(game, 1)
    pusher = Enum.at(final.stats, 1)

    assert {pusher.x, pusher.y} == {10, 10}
  end

  test "pusher with no step direction doesn't move" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: pusher_stat(10, 10, 0, 0),
        element: @pusher
      )

    final = Pusher.tick(game, 1)
    pusher = Enum.at(final.stats, 1)

    assert {pusher.x, pusher.y} == {10, 10}
  end

  test "pusher shoves a boulder into empty space then advances into its vacated spot" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: pusher_stat(10, 10, 1, 0),
        element: @pusher
      )

    # Boulder immediately east, empty to its east.
    game = %{game | tiles: Map.put(game.tiles, {11, 10}, {24, 0x0F})}

    final = Pusher.tick(game, 1)

    assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == 0
    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 40
    assert Map.fetch!(final.tiles, {12, 10}) |> elem(0) == 24
  end

  test "pusher shoves a chain of boulders" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: pusher_stat(10, 10, 1, 0),
        element: @pusher
      )

    # Three boulders east of the pusher, then empty.
    tiles =
      Enum.reduce(11..13, game.tiles, fn x, acc ->
        Map.put(acc, {x, 10}, {24, 0x0F})
      end)

    game = %{game | tiles: tiles}

    final = Pusher.tick(game, 1)

    # Chain shifted one tile east: pusher at 11, boulders at 12..14.
    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 40
    assert Map.fetch!(final.tiles, {12, 10}) |> elem(0) == 24
    assert Map.fetch!(final.tiles, {13, 10}) |> elem(0) == 24
    assert Map.fetch!(final.tiles, {14, 10}) |> elem(0) == 24
  end

  test "pusher against an unpushable wall chain doesn't move" do
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: pusher_stat(10, 10, 1, 0),
        element: @pusher,
        walls: [{13, 10}]
      )

    # Two boulders east of the pusher; wall three east (blocks chain).
    tiles =
      game.tiles
      |> Map.put({11, 10}, {24, 0x0F})
      |> Map.put({12, 10}, {24, 0x0F})

    game = %{game | tiles: tiles}

    final = Pusher.tick(game, 1)
    pusher = Enum.at(final.stats, 1)

    assert {pusher.x, pusher.y} == {10, 10}
    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 24
    assert Map.fetch!(final.tiles, {12, 10}) |> elem(0) == 24
  end
end
