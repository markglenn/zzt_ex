defmodule ZztEx.Zzt.AI.TigerTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.AIFixture
  alias ZztEx.Zzt.Stat
  alias ZztEx.Zzt.AI.Tiger

  @tiger 42
  @bullet 18

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  defp tiger_stat(x, y, opts) do
    %Stat{
      x: x,
      y: y,
      cycle: 2,
      p1: Keyword.get(opts, :p1, 0),
      p2: Keyword.get(opts, :p2, 0)
    }
  end

  test "aligned tiger with max p2 eventually fires a bullet" do
    # Player directly below the tiger; high P2 means near-constant firing.
    # Tick repeatedly; a bullet stat should show up.
    game =
      AIFixture.game_with(
        player_xy: {10, 20},
        monster: tiger_stat(10, 10, p2: 0x7F),
        element: @tiger
      )

    final =
      Enum.reduce_while(1..20, game, fn _, acc ->
        acc = Tiger.tick(acc, 1)

        has_bullet? =
          Enum.any?(acc.stats, fn s ->
            case Map.get(acc.tiles, {s.x, s.y}) do
              {@bullet, _} -> true
              _ -> false
            end
          end)

        if has_bullet?, do: {:halt, acc}, else: {:cont, acc}
      end)

    assert Enum.any?(final.stats, fn s ->
             case Map.get(final.tiles, {s.x, s.y}) do
               {@bullet, _} -> true
               _ -> false
             end
           end)
  end

  test "non-aligned tiger doesn't waste shots on empty axis tries" do
    # Player at (30, 30); tiger at (10, 10). Neither axis within 2.
    game =
      AIFixture.game_with(
        player_xy: {30, 30},
        monster: tiger_stat(10, 10, p2: 0x7F),
        element: @tiger
      )

    final = Enum.reduce(1..10, game, fn _, acc -> Tiger.tick(acc, 1) end)

    refute Enum.any?(final.stats, fn s ->
             case Map.get(final.tiles, {s.x, s.y}) do
               {@bullet, _} -> true
               _ -> false
             end
           end)
  end
end
