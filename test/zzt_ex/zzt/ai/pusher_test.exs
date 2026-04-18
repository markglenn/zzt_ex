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
end
