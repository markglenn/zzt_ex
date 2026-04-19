defmodule ZztEx.Zzt.AI.Bomb do
  @moduledoc """
  Port of `ElementBombTick` and the bomb branch of
  `DrawPlayerSurroundings` from reconstruction-of-zzt.

  An armed bomb's P1 counts down each cycle from 9:

    * `P1` in 2..9 — idle tick (beep in the reference; we're silent)
    * `P1` transitioning 2→1 — the explosion paints a blast radius of
      colored Breakables, damages destructibles, sends `:BOMBED` to any
      Object/Scroll in range
    * `P1` transitioning 1→0 — the cleanup pass turns those Breakables
      back into Empty and the bomb stat is removed

  Radius uses the torch ellipse `(ix-x)^2 + (iy-y)^2*2 < 50`, iterated
  over a `[-TORCH_DX-1..+TORCH_DX+1] x [-TORCH_DY-1..+TORCH_DY+1]` box.
  """

  alias ZztEx.Zzt.{Element, Game, Oop, Stat}

  @torch_dx 8
  @torch_dy 5
  @torch_dist_sqr 50

  @empty 0
  @breakable 23
  @scroll 10
  @star 15
  @object 36

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)

    cond do
      stat.p1 <= 0 ->
        game

      stat.p1 == 2 ->
        game
        |> set_p1(stat_idx, 1)
        |> explode(stat.x, stat.y)

      stat.p1 == 1 ->
        cleanup(game, stat.x, stat.y)
        |> Game.remove_stat(stat_idx)

      true ->
        set_p1(game, stat_idx, stat.p1 - 1)
    end
  end

  defp set_p1(game, stat_idx, new_p1) do
    stat = Enum.at(game.stats, stat_idx)
    %{game | stats: List.replace_at(game.stats, stat_idx, %Stat{stat | p1: new_p1})}
  end

  # Phase 1: within the ellipse around (x, y), send BOMBED to any
  # Object/Scroll stat, damage destructibles and stars, then turn any
  # Empty or Breakable into a colored Breakable (the "fireball" effect).
  defp explode(game, x, y) do
    Enum.reduce(radius_tiles(x, y), game, &ignite_tile/2)
  end

  defp ignite_tile({ix, iy}, game) do
    game
    |> notify_oop(ix, iy)
    |> damage_if_destructible(ix, iy)
    |> paint_fireball(ix, iy)
  end

  defp notify_oop(game, ix, iy) do
    case Game.tile_at(game, ix, iy) do
      {elem, _} when elem in [@object, @scroll] ->
        case find_stat_at(game.stats, ix, iy) do
          nil -> game
          # Stat 0 (the player) never listens for BOMBED, and the
          # reference guards against it explicitly.
          0 -> game
          idx -> game |> Oop.send(-idx, "BOMBED") |> Oop.tick(idx)
        end

      _ ->
        game
    end
  end

  defp damage_if_destructible(game, ix, iy) do
    case Game.tile_at(game, ix, iy) do
      {elem, _} ->
        if Element.destructible?(elem) or elem == @star do
          Game.damage_tile(game, ix, iy)
        else
          game
        end

      nil ->
        game
    end
  end

  defp paint_fireball(game, ix, iy) do
    case Game.tile_at(game, ix, iy) do
      {elem, _} when elem == @empty or elem == @breakable ->
        color = 0x09 + (:rand.uniform(7) - 1)
        %{game | tiles: Map.put(game.tiles, {ix, iy}, {@breakable, color})}

      _ ->
        game
    end
  end

  # Phase 2: turn any Breakable inside the radius back into Empty. This
  # both clears the fireball cells painted by phase 1 and wipes any
  # pre-existing Breakable that happened to sit in range.
  defp cleanup(game, x, y) do
    Enum.reduce(radius_tiles(x, y), game, fn {ix, iy}, acc ->
      case Game.tile_at(acc, ix, iy) do
        {@breakable, _} ->
          %{acc | tiles: Map.put(acc.tiles, {ix, iy}, {@empty, 0x0F})}

        _ ->
          acc
      end
    end)
  end

  defp radius_tiles(x, y) do
    for ix <- (x - @torch_dx - 1)..(x + @torch_dx + 1),
        iy <- (y - @torch_dy - 1)..(y + @torch_dy + 1),
        in_bounds?(ix, iy),
        :math.pow(ix - x, 2) + :math.pow(iy - y, 2) * 2 < @torch_dist_sqr,
        do: {ix, iy}
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s -> s.x == x and s.y == y end)
  end
end
