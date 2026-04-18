defmodule ZztEx.Zzt.AI.Bullet do
  @moduledoc """
  One-to-one port of `ElementBulletTick` from reconstruction-of-zzt,
  minus the ricochet branch (CP437 0x2A ricochets are TODO) and the
  OOP `:shot` send for Objects/Scrolls.

  Each tick the bullet tries to step into the tile ahead. Three cases:

    * Target is walkable or water → bullet moves in, stays alive.
    * Target is breakable or destructible-and-matches-source → award
      the target's ScoreValue, damage the target, bullet dies.
    * Otherwise → bullet just dies (hit a wall).

  `stat.p1` holds the shot source (0 = player, ≠0 = enemy). The
  destructible-match rule keeps player bullets from killing the player
  and keeps enemy bullets from friendly-firing other monsters.
  """

  alias ZztEx.Zzt.{Element, Game}

  @water 19
  @player 4

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    tx = stat.x + stat.step_x
    ty = stat.y + stat.step_y

    case Map.get(game.tiles, {tx, ty}) do
      nil ->
        Game.remove_stat(game, stat_idx)

      {element, _color} ->
        handle_target(game, stat_idx, stat, element, tx, ty)
    end
  end

  defp handle_target(game, stat_idx, stat, element, tx, ty) do
    cond do
      Element.walkable?(element) or element == @water ->
        Game.move_stat(game, stat_idx, tx, ty)

      damages?(element, stat.p1) ->
        game
        |> add_score(element)
        |> Game.damage_tile(tx, ty)
        |> Game.remove_stat(stat_idx)

      true ->
        Game.remove_stat(game, stat_idx)
    end
  end

  # Reference's bullet damage clause: breakables always take the hit,
  # destructibles only if the target is the player OR the shooter was
  # the player (`P1 = 0`). Prevents enemies from fragging each other
  # and player bullets from hitting the player.
  @breakable 23
  defp damages?(@breakable, _p1), do: true

  defp damages?(element, p1) do
    Element.destructible?(element) and (element == @player or p1 == 0)
  end

  defp add_score(game, element) do
    case Element.score_value(element) do
      0 -> game
      n -> %{game | player: %{game.player | score: game.player.score + n}}
    end
  end
end
