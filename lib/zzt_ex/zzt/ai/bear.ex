defmodule ZztEx.Zzt.AI.Bear do
  @moduledoc """
  Bear tick behavior, ported from ZZT's `ElementBearTick`.

  Bears are sensitivity-based: `p1` (0-8) is the detection range. A bear
  only closes on the player when the player is within `p1` tiles on the
  perpendicular axis of approach:

    * If the horizontal gap is ≤ p1, step vertically toward the player.
    * Otherwise if the vertical gap is ≤ p1, step horizontally.
    * Otherwise don't move.

  Bears also break through Breakable walls on contact (the wall is
  destroyed, the bear stays put). On player contact, they deal 10 damage
  and die, mirroring Lion.
  """

  alias ZztEx.Zzt.{Element, Game}
  alias ZztEx.Zzt.AI.Directions

  @breakable 23

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    bear = Enum.at(game.stats, stat_idx)
    player = Enum.at(game.stats, 0)

    {dx, dy} = seek_within_range(bear, player)
    tx = bear.x + dx
    ty = bear.y + dy

    cond do
      dx == 0 and dy == 0 -> game
      not in_bounds?(tx, ty) -> game
      tx == player.x and ty == player.y -> Game.collide_with_player(game, stat_idx)
      breakable_at?(game, tx, ty) -> smash(game, tx, ty)
      walkable?(game, tx, ty) -> Game.move_stat(game, stat_idx, tx, ty)
      true -> game
    end
  end

  # Prefer vertical approach when we're already close on the X axis, then
  # horizontal if we're already close on Y, else don't move.
  defp seek_within_range(bear, player) do
    dy =
      if abs(player.x - bear.x) <= bear.p1 do
        Directions.signum(player.y - bear.y)
      else
        0
      end

    dx =
      if dy == 0 and abs(player.y - bear.y) <= bear.p1 do
        Directions.signum(player.x - bear.x)
      else
        0
      end

    {dx, dy}
  end

  defp breakable_at?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {@breakable, _} -> true
      _ -> false
    end
  end

  # ZZT's bear doesn't occupy the wall it smashes — the wall just becomes
  # empty, the bear stays where it was, and it'll try again next tick.
  defp smash(game, x, y) do
    %{game | tiles: Map.put(game.tiles, {x, y}, {0, 0x0F})}
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element)
    end
  end
end
