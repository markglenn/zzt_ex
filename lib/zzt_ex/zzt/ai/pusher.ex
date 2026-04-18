defmodule ZztEx.Zzt.AI.Pusher do
  @moduledoc """
  One-to-one port of `ElementPusherTick`.

  Each tick the pusher tries to step in its stored `step` direction.
  Reference also calls `ElementPushablePush` on blocked tiles so the
  pusher can shove a pushable block out of the way — that path is a
  no-op here until pushable blocks (boulder, sliders) land.

  On a successful move the pusher recursively ticks any other pusher
  immediately behind it with the same step — so a column of pushers
  all march together on the same stat pass, matching ZZT's domino.
  """

  alias ZztEx.Zzt.{Element, Game}

  @pusher 40

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    pusher = Enum.at(game.stats, stat_idx)
    start_x = pusher.x
    start_y = pusher.y
    sx = pusher.step_x
    sy = pusher.step_y

    cond do
      sx == 0 and sy == 0 ->
        game

      walkable?(game, pusher.x + sx, pusher.y + sy) ->
        game
        |> Game.move_stat(stat_idx, pusher.x + sx, pusher.y + sy)
        |> chain_behind(start_x, start_y, sx, sy)

      true ->
        game
    end
  end

  # If another pusher sits one tile behind the original position and is
  # walking the same direction, tick it so the whole column moves in a
  # single stat pass. Reference computes `(X - 2*StepX, Y - 2*StepY)`
  # from the *new* head position, which simplifies to one step behind
  # the old head.
  defp chain_behind(game, old_x, old_y, sx, sy) do
    bx = old_x - sx
    by = old_y - sy

    with {@pusher, _} <- Game.tile_at(game, bx, by) || :none,
         idx when is_integer(idx) <- find_stat_at(game.stats, bx, by),
         %{step_x: ^sx, step_y: ^sy} <- Enum.at(game.stats, idx) do
      tick(game, idx)
    else
      _ -> game
    end
  end

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s -> s.x == x and s.y == y end)
  end

  defp walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element)
    end
  end
end
