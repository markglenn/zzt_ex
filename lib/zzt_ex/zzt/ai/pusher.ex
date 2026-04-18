defmodule ZztEx.Zzt.AI.Pusher do
  @moduledoc """
  One-to-one port of `ElementPusherTick`.

      startX := X; startY := Y
      if not Walkable(X+StepX, Y+StepY):
        ElementPushablePush(X+StepX, Y+StepY, StepX, StepY)

      statId := GetStatIdAt(startX, startY)
      if Walkable(X+StepX, Y+StepY):
        MoveStat  # and queue the push sound
        if pusher at (X - 2*StepX, Y - 2*StepY) with same step:
          TickProc(that pusher)  # domino

  A blocked pusher calls `Game.push_tile/4`, which may shove an entire
  chain of pushable tiles forward. After the push we re-acquire the
  pusher by position because damage from crushed tiles could have
  shifted stat indices.
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

      true ->
        game = maybe_push(game, pusher.x + sx, pusher.y + sy, sx, sy)

        case find_stat_at(game.stats, start_x, start_y) do
          nil ->
            game

          cur_idx ->
            if walkable?(game, start_x + sx, start_y + sy) do
              game
              |> Game.move_stat(cur_idx, start_x + sx, start_y + sy)
              |> chain_behind(start_x, start_y, sx, sy)
            else
              game
            end
        end
    end
  end

  defp maybe_push(game, x, y, sx, sy) do
    if walkable?(game, x, y), do: game, else: Game.push_tile(game, x, y, sx, sy)
  end

  # Domino: if another pusher with the same step sits one tile behind the
  # pusher's old position, tick it in the same pass so a column marches
  # together.
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
