defmodule ZztEx.Zzt.AI.Pusher do
  @moduledoc """
  Pusher tick behavior.

  Pushers constantly march in their stored step direction. This is the
  simplified first pass: the pusher moves into the target tile if it's
  walkable, otherwise it stays put. ZZT's pushers also shove boulders,
  sliders, and other pushable objects along their path — that arrives
  once pushable-block mechanics land alongside player input.
  """

  alias ZztEx.Zzt.{Element, Game}

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    pusher = Enum.at(game.stats, stat_idx)
    tx = pusher.x + pusher.step_x
    ty = pusher.y + pusher.step_y

    cond do
      pusher.step_x == 0 and pusher.step_y == 0 -> game
      not in_bounds?(tx, ty) -> game
      walkable?(game, tx, ty) -> Game.move_stat(game, stat_idx, tx, ty)
      true -> game
    end
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element)
    end
  end
end
