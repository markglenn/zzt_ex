defmodule ZztEx.Zzt.Touch do
  @moduledoc """
  Per-element touch procedures, fired when a stat (typically the player)
  walks onto a tile. Ports the `ElementXxxTouch` procs from
  `reconstruction-of-zzt/SRC/ELEMENTS.PAS`.

  Each procedure takes the current `Game`, the touched position, the
  source stat id (0 for the player), and the movement delta. It returns
  `{game, dx, dy}` — an updated game plus the new movement delta. A
  delta of `{0, 0}` blocks the mover from advancing onto the tile.
  """

  alias ZztEx.Zzt.{Element, Game, Stat}

  @type delta :: integer()
  @type result :: {Game.t(), delta(), delta()}

  # Element IDs we care about (kept local to make the dispatch table
  # readable without a big @-constant salad).
  @ammo 5
  @torch 6
  @gem 7
  @key 8
  @door 9
  @energizer 14
  @water 19
  @forest 20
  @breakable 23
  @fake 27
  @invisible 28
  @slime 37

  @passage 11
  @boulder 24
  @slider_ns 25
  @slider_ew 26

  # Every monster/projectile that hurts the player on contact.
  @damaging [15, 18, 34, 35, 41, 42, 44, 45]

  @doc """
  Run the touch procedure for whatever is at `(x, y)`.
  """
  @spec touch(Game.t(), integer(), integer(), non_neg_integer(), delta(), delta()) :: result()
  def touch(%Game{} = game, x, y, source_idx, dx, dy) do
    case Game.tile_at(game, x, y) do
      {element, color} -> dispatch(element, color, game, x, y, source_idx, dx, dy)
      nil -> {game, dx, dy}
    end
  end

  # ---- pickups -----------------------------------------------------------

  defp dispatch(@ammo, _color, game, x, y, _src, dx, dy) do
    game
    |> update_player(fn p -> %{p | ammo: p.ammo + 5} end)
    |> empty_tile(x, y)
    |> with_delta(dx, dy)
  end

  defp dispatch(@gem, _color, game, x, y, _src, dx, dy) do
    game
    |> update_player(fn p ->
      %{p | gems: p.gems + 1, health: p.health + 1, score: p.score + 10}
    end)
    |> empty_tile(x, y)
    |> with_delta(dx, dy)
  end

  defp dispatch(@torch, _color, game, x, y, _src, dx, dy) do
    game
    |> update_player(fn p -> %{p | torches: p.torches + 1} end)
    |> empty_tile(x, y)
    |> with_delta(dx, dy)
  end

  defp dispatch(@energizer, _color, game, x, y, _src, dx, dy) do
    game
    |> update_player(fn p -> %{p | energizer_ticks: 75} end)
    |> empty_tile(x, y)
    |> with_delta(dx, dy)
  end

  # Key color low nibble mod 8 gives slot 1..7 → our 0-indexed 0..6.
  # Already-owned key: tile stays, player bounces off.
  defp dispatch(@key, color, game, x, y, _src, dx, dy) do
    case key_slot(color) do
      slot when slot in 0..6 ->
        if Enum.at(game.player.keys, slot) do
          {game, 0, 0}
        else
          game
          |> update_player(fn p -> %{p | keys: List.replace_at(p.keys, slot, true)} end)
          |> empty_tile(x, y)
          |> with_delta(dx, dy)
        end

      _ ->
        {game, dx, dy}
    end
  end

  # Door high nibble mod 8 gives the required key slot. Unlocks with the
  # key (consumed), letting the player walk through; otherwise blocks.
  defp dispatch(@door, color, game, x, y, _src, dx, dy) do
    slot = rem(div(color, 16), 8) - 1

    case slot do
      s when s in 0..6 ->
        if Enum.at(game.player.keys, s) do
          game
          |> update_player(fn p -> %{p | keys: List.replace_at(p.keys, s, false)} end)
          |> empty_tile(x, y)
          |> with_delta(dx, dy)
        else
          {game, 0, 0}
        end

      _ ->
        {game, 0, 0}
    end
  end

  # ---- environment -------------------------------------------------------

  # Forest is chopped down — tile becomes empty, player walks through.
  defp dispatch(@forest, _color, game, x, y, _src, dx, dy) do
    game |> empty_tile(x, y) |> with_delta(dx, dy)
  end

  # Invisible wall: reveal as Normal wall and block the mover.
  defp dispatch(@invisible, color, game, x, y, _src, _dx, _dy) do
    {put_tile(game, x, y, {22, color}), 0, 0}
  end

  # Fake wall is informational — player walks through unaltered.
  defp dispatch(@fake, _color, game, _x, _y, _src, dx, dy), do: {game, dx, dy}

  # Water splashes but blocks forward motion.
  defp dispatch(@water, _color, game, _x, _y, _src, _dx, _dy), do: {game, 0, 0}

  # Pushable: try to shove the block; if it moves out of the way the
  # outer walkable check lets the mover slide into the vacated tile.
  defp dispatch(element, _color, game, x, y, _src, dx, dy)
       when element in [@boulder, @slider_ns, @slider_ew] do
    {Game.push_tile(game, x, y, dx, dy), dx, dy}
  end

  # Passage: teleport to the matching-color passage on the board stored
  # in the passage stat's p3. Delta is cleared so the outer move loop
  # doesn't also try to slide the player onto the old passage tile.
  defp dispatch(@passage, _color, game, x, y, _src, _dx, _dy) do
    {Game.passage_teleport(game, x, y), 0, 0}
  end

  # Slime: slime dies and the tile becomes a breakable wall in its color.
  # Player isn't damaged — that's reference behavior (SlimeTouch calls
  # DamageStat on the slime, not the source).
  defp dispatch(@slime, color, game, x, y, _src, _dx, _dy) do
    game =
      case find_stat_at(game.stats, x, y) do
        nil -> game
        idx -> Game.remove_stat(game, idx)
      end

    {put_tile(game, x, y, {@breakable, color}), 0, 0}
  end

  # ---- damaging ---------------------------------------------------------

  defp dispatch(element, _color, game, x, y, source_idx, dx, dy)
       when element in @damaging and source_idx == 0 do
    # Player walking into a monster. BoardAttack semantics: when energized,
    # score += monster.ScoreValue and the monster dies; otherwise the
    # player takes 10 damage and the monster still dies. Either way the
    # tile (and any stat at it) goes away, so the player advances onto it.
    game =
      if Game.energized?(game) do
        update_player(game, fn p -> %{p | score: p.score + Element.score_value(element)} end)
      else
        Game.damage_player(game, 10)
      end

    game =
      case find_stat_at(game.stats, x, y) do
        nil -> empty_tile(game, x, y)
        idx -> Game.remove_stat(game, idx)
      end

    {game, dx, dy}
  end

  # Non-player source walking into a damaging tile (e.g. a bullet
  # crossing a lion): symmetric BoardAttack — attacker dies, target is
  # removed. Player damage falls through the src=0 branch above.
  defp dispatch(element, _color, game, x, y, source_idx, dx, dy) when element in @damaging do
    game =
      case find_stat_at(game.stats, x, y) do
        nil -> empty_tile(game, x, y)
        idx -> Game.remove_stat(game, idx)
      end

    game =
      if source_idx > 0 and source_idx < length(game.stats) do
        Game.remove_stat(game, source_idx)
      else
        game
      end

    {game, dx, dy}
  end

  # ---- default -----------------------------------------------------------

  defp dispatch(_element, _color, game, _x, _y, _src, dx, dy), do: {game, dx, dy}

  # ---- helpers -----------------------------------------------------------

  defp update_player(game, fun), do: %{game | player: fun.(game.player)}
  defp put_tile(game, x, y, tile), do: %{game | tiles: Map.put(game.tiles, {x, y}, tile)}
  defp empty_tile(game, x, y), do: put_tile(game, x, y, {0, 0x0F})
  defp with_delta(game, dx, dy), do: {game, dx, dy}

  defp key_slot(color), do: rem(color, 8) - 1

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s ->
      %Stat{} = s
      s.x == x and s.y == y
    end)
  end
end
