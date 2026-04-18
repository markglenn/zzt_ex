defmodule ZztEx.Zzt.AI.Shark do
  @moduledoc """
  One-to-one port of `ElementSharkTick`. Identical to Lion except the
  only tile a shark can swim onto is Water.
  """

  alias ZztEx.Zzt.Game
  alias ZztEx.Zzt.AI.Directions

  @water 19
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
      water?(game, tx, ty) -> Game.move_stat(game, stat_idx, tx, ty)
      player_at?(game, tx, ty) -> Game.collide_with_player(game, stat_idx)
      true -> game
    end
  end

  defp water?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {@water, _} -> true
      _ -> false
    end
  end

  defp player_at?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {@player, _} -> true
      _ -> false
    end
  end
end
