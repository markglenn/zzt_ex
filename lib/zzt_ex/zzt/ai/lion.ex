defmodule ZztEx.Zzt.AI.Lion do
  @moduledoc """
  One-to-one port of `ElementLionTick` from reconstruction-of-zzt.

      if P1 < Random(10) then
        CalcDirectionRnd(deltaX, deltaY)
      else
        CalcDirectionSeek(X, Y, deltaX, deltaY);

      if Walkable(X+dx, Y+dy) then MoveStat
      else if Player(X+dx, Y+dy) then BoardAttack

  `p1` is intelligence: higher means more likely to chase. The direction
  chosen by `CalcDirectionSeek` already accounts for the energizer (flees
  instead of chasing when active), so there's no extra inversion here.
  """

  alias ZztEx.Zzt.{Element, Game}
  alias ZztEx.Zzt.AI.Directions

  @player 4

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)

    {dx, dy} =
      if stat.p1 < :rand.uniform(10) - 1 do
        Directions.random_step()
      else
        Directions.seek(game, stat)
      end

    tx = stat.x + dx
    ty = stat.y + dy

    cond do
      walkable?(game, tx, ty) -> Game.move_stat(game, stat_idx, tx, ty)
      player_at?(game, tx, ty) -> Game.collide_with_player(game, stat_idx)
      true -> game
    end
  end

  defp walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element)
    end
  end

  defp player_at?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {@player, _} -> true
      _ -> false
    end
  end
end
