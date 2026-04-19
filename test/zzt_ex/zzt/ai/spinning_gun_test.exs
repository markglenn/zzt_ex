defmodule ZztEx.Zzt.AI.SpinningGunTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.SpinningGun

  @spinning_gun 39
  @bullet 18
  @star 15

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  defp gun_stat(x, y, opts) do
    %Stat{
      x: x,
      y: y,
      cycle: 2,
      p1: Keyword.get(opts, :p1, 0),
      p2: Keyword.get(opts, :p2, 0)
    }
  end

  defp has_projectile?(game, element) do
    Enum.any?(game.stats, fn s ->
      case Map.get(game.tiles, {s.x, s.y}) do
        {^element, _} -> true
        _ -> false
      end
    end)
  end

  test "gun with high firing rate shoots bullets by default" do
    game =
      AIFixture.game_with(
        player_xy: {10, 20},
        monster: gun_stat(10, 10, p2: 0x7F),
        element: @spinning_gun
      )

    final =
      Enum.reduce_while(1..20, game, fn _, acc ->
        next = SpinningGun.tick(acc, 1)
        if has_projectile?(next, @bullet), do: {:halt, next}, else: {:cont, next}
      end)

    assert has_projectile?(final, @bullet)
  end

  test "gun with P2 high bit set fires stars" do
    # High bit (0x80) toggles the projectile type. Low 7 bits = 0x7F
    # for a high firing rate.
    game =
      AIFixture.game_with(
        player_xy: {10, 20},
        monster: gun_stat(10, 10, p2: 0xFF),
        element: @spinning_gun
      )

    final =
      Enum.reduce_while(1..20, game, fn _, acc ->
        next = SpinningGun.tick(acc, 1)
        if has_projectile?(next, @star), do: {:halt, next}, else: {:cont, next}
      end)

    assert has_projectile?(final, @star)
  end
end
