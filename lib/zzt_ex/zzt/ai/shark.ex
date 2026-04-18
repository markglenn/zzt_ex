defmodule ZztEx.Zzt.AI.Shark do
  @moduledoc """
  Shark tick behavior, ported from ZZT's `ElementSharkTick`.

  Shark is essentially a Lion that swims: it picks a direction with
  `p1`-weighted seek-or-random, but can only move onto Water tiles. If
  the chosen direction lands on the player it attacks; any other
  non-water tile blocks the shark in place.
  """

  alias ZztEx.Zzt.Game
  alias ZztEx.Zzt.AI.Directions

  @water 19

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    shark = Enum.at(game.stats, stat_idx)
    player = Enum.at(game.stats, 0)

    {dx, dy} = direction(shark, player, Game.energized?(game))
    tx = shark.x + dx
    ty = shark.y + dy

    cond do
      not in_bounds?(tx, ty) -> game
      tx == player.x and ty == player.y -> Game.collide_with_player(game, stat_idx)
      water?(game, tx, ty) -> Game.move_stat(game, stat_idx, tx, ty)
      true -> game
    end
  end

  defp direction(stat, player, energized?) do
    {dx, dy} =
      if :rand.uniform(10) - 1 < stat.p1 do
        Directions.seek(stat, player)
      else
        Directions.random_step()
      end

    if energized?, do: {-dx, -dy}, else: {dx, dy}
  end

  defp water?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {@water, _color} -> true
      _ -> false
    end
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25
end
