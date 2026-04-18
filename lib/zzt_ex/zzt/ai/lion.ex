defmodule ZztEx.Zzt.AI.Lion do
  @moduledoc """
  Lion tick behavior, ported from ZZT's `ElementLionTick`.

  Each lion picks a direction then either moves into that tile, attacks
  the player if it's there, or does nothing if blocked:

    1. With probability `p1 / 10`, seek the player; otherwise pick a
       random cardinal direction.
    2. If the player is energized, invert the chosen direction — lions
       run away from an energized player.
    3. Walk into the tile if it's `Element.walkable?/1`; attack if it's
       the player; otherwise stay put.
  """

  alias ZztEx.Zzt.{Element, Game}
  alias ZztEx.Zzt.AI.Directions

  @doc """
  Run one tick for the lion at `stat_idx`. Returns the updated game.
  """
  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    player = Enum.at(game.stats, 0)

    {dx, dy} = direction(stat, player, Game.energized?(game))
    tx = stat.x + dx
    ty = stat.y + dy

    cond do
      not in_bounds?(tx, ty) -> game
      tx == player.x and ty == player.y -> Game.collide_with_player(game, stat_idx)
      walkable?(game, tx, ty) -> Game.move_stat(game, stat_idx, tx, ty)
      true -> game
    end
  end

  # `Random(0, 9) < p1` selects seek; p1 is the "intelligence" stored on
  # the stat (0 = always random, 8-9 = nearly always chases).
  defp direction(stat, player, energized?) do
    {dx, dy} =
      if :rand.uniform(10) - 1 < stat.p1 do
        Directions.seek(stat, player)
      else
        Directions.random_step()
      end

    if energized?, do: {-dx, -dy}, else: {dx, dy}
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element)
    end
  end
end
