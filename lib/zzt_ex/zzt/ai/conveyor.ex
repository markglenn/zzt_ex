defmodule ZztEx.Zzt.AI.Conveyor do
  @moduledoc """
  Conveyor CW / CCW tick, one-to-one port of `ElementConveyorTick` from
  reconstruction-of-zzt.

  A conveyor rotates its 8 diagonal neighbors around itself — tiles
  shuffle in a ring, cascading through chains of Pushable tiles until
  they hit a non-Pushable wall (which holds the chain in place).
  Clockwise and counter-clockwise differ only in iteration direction.
  """

  alias ZztEx.Zzt.{Element, Game}

  # DiagonalDeltaX/Y from GAME.PAS — 8 positions around the center in the
  # order ZZT iterates them. Not in strict compass order; iterating 0→7
  # with +1 step drives tiles clockwise, -1 step drives CCW.
  @deltas {
    {-1, 1},
    {0, 1},
    {1, 1},
    {1, 0},
    {1, -1},
    {0, -1},
    {-1, -1},
    {-1, 0}
  }

  @doc "Clockwise conveyor tick — direction = +1."
  @spec cw_tick(Game.t(), non_neg_integer()) :: Game.t()
  def cw_tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    rotate(game, stat.x, stat.y, 1)
  end

  @doc "Counter-clockwise conveyor tick — direction = -1."
  @spec ccw_tick(Game.t(), non_neg_integer()) :: Game.t()
  def ccw_tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    rotate(game, stat.x, stat.y, -1)
  end

  defp rotate(game, x, y, direction) do
    snapshot = capture(game, x, y)
    iter = iteration(direction)

    # First pass collects tiles and computes the initial `canMove`. The
    # reference walks once, updating canMove based on each tile; its
    # value at the end carries into the second pass.
    initial_can_move = compute_initial_can_move(snapshot, iter)

    {new_game, _} =
      Enum.reduce(iter, {game, initial_can_move}, fn i, {acc, can_move} ->
        process(acc, x, y, direction, snapshot, i, can_move)
      end)

    new_game
  end

  defp capture(game, x, y) do
    @deltas
    |> Tuple.to_list()
    |> Enum.map(fn {dx, dy} ->
      Map.get(game.tiles, {x + dx, y + dy}, {0, 0})
    end)
    |> List.to_tuple()
  end

  defp iteration(1), do: 0..7
  defp iteration(-1), do: 7..0//-1

  defp compute_initial_can_move(snapshot, iter) do
    Enum.reduce(iter, true, fn i, can_move ->
      case elem(snapshot, i) do
        {0, _} -> true
        {element, _} -> if Element.pushable?(element), do: can_move, else: false
      end
    end)
  end

  defp process(game, x, y, direction, snapshot, i, can_move) do
    {element, _color} = elem(snapshot, i)

    cond do
      can_move and element == 0 ->
        {game, true}

      can_move and Element.pushable?(element) ->
        game
        |> move_tile(x, y, direction, i)
        |> maybe_clear_trailing_spot(x, y, direction, snapshot, i)
        |> then(&{&1, true})

      can_move ->
        # Non-pushable, non-empty: chain ends here.
        {game, false}

      element == 0 ->
        {game, true}

      true ->
        {game, false}
    end
  end

  # Move whatever lives at position `i` into position `i - direction` in
  # the diagonal ring. `Game.element_move/5` handles stat-owning tiles
  # (Player, Lion, etc.) via `move_stat` and pure tiles (Boulder, Gem)
  # via direct tile translation.
  defp move_tile(game, x, y, direction, i) do
    {src_dx, src_dy} = elem(@deltas, i)
    {dst_dx, dst_dy} = elem(@deltas, wrap(i - direction))

    Game.element_move(game, x + src_dx, y + src_dy, x + dst_dx, y + dst_dy)
  end

  # If the next tile in the iteration order *isn't* pushable, nothing
  # will slide into the slot we just vacated. Reference explicitly
  # clears that slot to prevent the just-moved tile from ghost-appearing
  # there. When the next tile IS pushable, we leave the slot alone —
  # the next iteration will overwrite it.
  defp maybe_clear_trailing_spot(game, x, y, direction, snapshot, i) do
    next_i = wrap(i + direction)
    {next_elem, _} = elem(snapshot, next_i)

    if Element.pushable?(next_elem) do
      game
    else
      {dx, dy} = elem(@deltas, i)
      %{game | tiles: Map.put(game.tiles, {x + dx, y + dy}, {0, 0})}
    end
  end

  defp wrap(i), do: rem(i + 8, 8)
end
