defmodule ZztEx.Zzt.AI.Slime do
  @moduledoc """
  One-to-one port of `ElementSlimeTick`.

  Each tick `p1` increments until it reaches `p2` (the growth-speed
  threshold). On the tick `p1 == p2`:

    1. Reset `p1` to 0.
    2. Walk the four cardinal neighbors in N/S/W/E order (ZZT's
       `NeighborDelta` order). Every walkable tile is a candidate.
    3. The first walkable becomes the slime's new position; the
       vacated tile becomes Breakable in the slime's color.
    4. Every subsequent walkable spawns a new Slime stat — this is
       how slime colonies grow.
    5. If no walkable neighbor exists, the slime dies: remove the stat
       and turn its tile into Breakable.

  Slime doesn't attack via its tick — player damage comes from
  `ElementSlimeTouch`, fired when the player walks onto the slime tile.
  """

  alias ZztEx.Zzt.{Element, Game, Stat}

  @breakable 23
  @slime 37
  @slime_cycle 3

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    slime = Enum.at(game.stats, stat_idx)

    if slime.p1 < slime.p2 do
      update_stat(game, stat_idx, fn s -> %Stat{s | p1: s.p1 + 1} end)
    else
      spread(game, stat_idx, slime)
    end
  end

  defp spread(game, stat_idx, slime) do
    {_, color} = Map.fetch!(game.tiles, {slime.x, slime.y})
    game = update_stat(game, stat_idx, fn s -> %Stat{s | p1: 0} end)

    walkable =
      neighbor_deltas()
      |> Enum.filter(fn {dx, dy} ->
        tile_walkable?(game, slime.x + dx, slime.y + dy)
      end)

    case walkable do
      [] ->
        die(game, stat_idx, slime, color)

      [first | rest] ->
        game = move_and_trail(game, stat_idx, slime, first, color)

        Enum.reduce(rest, game, fn {dx, dy}, acc ->
          replicate(acc, slime.x + dx, slime.y + dy, color, slime.p2)
        end)
    end
  end

  # Move the slime tile to its new position and convert the old position
  # into a Breakable of the slime's color. Unlike `Game.move_stat`, the
  # vacated tile *doesn't* get restored to `under` — it stays as part of
  # the slime's breakable trail.
  defp move_and_trail(game, stat_idx, slime, {dx, dy}, color) do
    tx = slime.x + dx
    ty = slime.y + dy
    {target_elem, target_color} = Map.fetch!(game.tiles, {tx, ty})

    tiles =
      game.tiles
      |> Map.put({slime.x, slime.y}, {@breakable, color})
      |> Map.put({tx, ty}, {@slime, color})

    updated = %Stat{
      slime
      | x: tx,
        y: ty,
        under_element: target_elem,
        under_color: target_color,
        p1: 0
    }

    %{game | tiles: tiles, stats: List.replace_at(game.stats, stat_idx, updated)}
  end

  # Spawn a new slime at (x, y) with cycle 3 and inherited P2, matching
  # `AddStat + Board.Stats[last].P2 := P2` in the reference.
  defp replicate(game, x, y, color, p2) do
    Game.add_stat(
      game,
      x,
      y,
      @slime,
      color,
      %Stat{x: 0, y: 0, cycle: @slime_cycle, p2: p2}
    )
  end

  # No walkable neighbors: remove the stat, tile becomes breakable.
  # We bypass Game.remove_stat's under-restore because the reference
  # explicitly writes breakable at the old position.
  defp die(game, stat_idx, slime, color) do
    tiles = Map.put(game.tiles, {slime.x, slime.y}, {@breakable, color})
    stats = List.delete_at(game.stats, stat_idx)
    %{game | tiles: tiles, stats: stats}
  end

  # Reference ZZT's NeighborDelta order: N, S, W, E.
  defp neighbor_deltas, do: [{0, -1}, {0, 1}, {-1, 0}, {1, 0}]

  defp tile_walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {element, _} -> Element.walkable?(element)
      nil -> false
    end
  end

  defp update_stat(game, stat_idx, fun) do
    stat = Enum.at(game.stats, stat_idx)
    %{game | stats: List.replace_at(game.stats, stat_idx, fun.(stat))}
  end
end
