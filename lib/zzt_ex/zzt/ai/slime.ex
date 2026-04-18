defmodule ZztEx.Zzt.AI.Slime do
  @moduledoc """
  Slime tick behavior, ported from ZZT's `ElementSlimeTick`.

  Slime grows slowly: every tick it increments `p1` until `p1 >= p2`
  (the configured "growth speed"), then it tries to step. It picks a
  random walkable adjacent tile, moves there, and leaves behind a
  Breakable wall of its own color — the classic slime trail the player
  has to shoot through.

  On player contact, slime attacks like any contact monster: 10 damage
  and slime dies (or just dies if the player is energized).
  """

  alias ZztEx.Zzt.{Element, Game, Stat}

  @breakable 23

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    slime = Enum.at(game.stats, stat_idx)

    if slime.p1 < slime.p2 do
      updated = %Stat{slime | p1: slime.p1 + 1}
      %{game | stats: List.replace_at(game.stats, stat_idx, updated)}
    else
      grow(game, stat_idx)
    end
  end

  defp grow(game, stat_idx) do
    slime = Enum.at(game.stats, stat_idx)
    player = Enum.at(game.stats, 0)

    candidates =
      [{-1, 0}, {1, 0}, {0, -1}, {0, 1}]
      |> Enum.filter(fn {dx, dy} ->
        tx = slime.x + dx
        ty = slime.y + dy
        in_bounds?(tx, ty) and reachable?(game, tx, ty, player)
      end)

    case candidates do
      [] ->
        game

      _ ->
        {dx, dy} = Enum.random(candidates)
        step(game, stat_idx, slime, player, dx, dy)
    end
  end

  defp step(game, stat_idx, slime, player, dx, dy) do
    tx = slime.x + dx
    ty = slime.y + dy

    if tx == player.x and ty == player.y do
      Game.collide_with_player(game, stat_idx)
    else
      spread(game, stat_idx, slime, tx, ty)
    end
  end

  # Custom move: the source tile becomes a Breakable (the slime's trail),
  # not the under-tile we'd normally restore. The slime's stat relocates
  # and remembers what was under the target so the breakable-trail chain
  # stays consistent if another mover walks over it.
  defp spread(game, stat_idx, slime, tx, ty) do
    slime_tile = Map.fetch!(game.tiles, {slime.x, slime.y})
    {_slime_elem, slime_color} = slime_tile
    {target_elem, target_color} = Map.fetch!(game.tiles, {tx, ty})

    new_tiles =
      game.tiles
      |> Map.put({slime.x, slime.y}, {@breakable, slime_color})
      |> Map.put({tx, ty}, slime_tile)

    updated = %Stat{
      slime
      | x: tx,
        y: ty,
        p1: 0,
        under_element: target_elem,
        under_color: target_color
    }

    %{game | tiles: new_tiles, stats: List.replace_at(game.stats, stat_idx, updated)}
  end

  defp reachable?(game, x, y, player) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element) or {x, y} == {player.x, player.y}
    end
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25
end
