defmodule ZztEx.Zzt.AI.StarTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Star

  @star 15

  defp star_stat(x, y, p2) do
    %Stat{x: x, y: y, cycle: 1, p2: p2}
  end

  test "star decrements P2 each tick" do
    game =
      AIFixture.game_with(
        player_xy: {5, 5},
        monster: star_stat(10, 10, 10),
        element: @star
      )

    final = Star.tick(game, 1)
    star = Enum.at(final.stats, 1)

    assert star.p2 == 9
  end

  test "star dies when P2 runs out" do
    game =
      AIFixture.game_with(
        player_xy: {5, 5},
        monster: star_stat(10, 10, 1),
        element: @star
      )

    final = Star.tick(game, 1)
    # Only the player stat remains.
    assert length(final.stats) == 1
  end

  test "star moves toward the player on even-P2 ticks" do
    # P2 starts at 100, after decrement is 99 (odd — no move this tick).
    # Tick twice to cross an even-P2 pass.
    game =
      AIFixture.game_with(
        player_xy: {5, 10},
        monster: star_stat(20, 10, 100),
        element: @star
      )

    final = Enum.reduce(1..2, game, fn _, acc -> Star.tick(acc, 1) end)
    star = Enum.at(final.stats, 1)

    # After two ticks the star has seeked and taken one cardinal step
    # toward the player (who's due west on the same row).
    assert star.x < 20
  end

  test "star attacking the player damages them and dies" do
    # Star directly east of the player; p2 = 2 so the first tick (p2=1)
    # skips, the second (p2=0) would kill the star... hmm. Use p2 = 3
    # so the first tick drops to 2 (even → step).
    game =
      AIFixture.game_with(
        player_xy: {10, 10},
        monster: star_stat(11, 10, 3),
        element: @star
      )

    final = Star.tick(game, 1)

    assert final.player.health == 90
    # Star removed after the collision.
    assert length(final.stats) == 1
  end
end
