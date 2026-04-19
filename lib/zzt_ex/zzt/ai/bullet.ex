defmodule ZztEx.Zzt.AI.Bullet do
  @moduledoc """
  One-to-one port of `ElementBulletTick`. Each tick the bullet tries to
  step into the tile ahead:

    * Target walkable or water → slide in, stay alive.
    * Target is a Ricochet (and this is the first try this tick) →
      reverse the step direction and try again.
    * Target is breakable or a source-matched destructible → award the
      target's ScoreValue, damage the target, bullet dies.
    * Otherwise, check the two tiles perpendicular to the bullet's path:
      a Ricochet on one side redirects the bullet 90° and retries; if
      neither is a Ricochet the bullet dies. When the blocker is an
      Object or Scroll the bullet's death also dispatches `:SHOT` on
      that stat's OOP program (ELEMENTS.PAS:382-385).

  `stat.p1` holds the shot source (0 = player, ≠0 = enemy). The
  destructible-match rule keeps player bullets from killing the player
  and keeps enemy bullets from friendly-firing other monsters.
  """

  alias ZztEx.Zzt.{Element, Game, Oop, Stat}

  @water 19
  @breakable 23
  @ricochet 32
  @player 4
  @scroll 10
  @object 36

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx), do: try_move(game, stat_idx, true)

  defp try_move(game, stat_idx, first_try?) do
    stat = Enum.at(game.stats, stat_idx)
    tx = stat.x + stat.step_x
    ty = stat.y + stat.step_y

    case Map.get(game.tiles, {tx, ty}) do
      nil ->
        Game.remove_stat(game, stat_idx)

      {element, _color} ->
        resolve(game, stat_idx, stat, element, tx, ty, first_try?)
    end
  end

  defp resolve(game, stat_idx, stat, element, tx, ty, first_try?) do
    cond do
      Element.walkable?(element) or element == @water ->
        Game.move_stat(game, stat_idx, tx, ty)

      element == @ricochet and first_try? ->
        game
        |> set_step(stat_idx, -stat.step_x, -stat.step_y)
        |> try_move(stat_idx, false)

      damages?(element, stat.p1) ->
        # Reference's BoardAttack: kill the attacker (bullet) first,
        # then damage the defender. Reversing the order would shift
        # `stat_idx` if `damage_tile` removed a stat at a lower index
        # (e.g. shooting a monster whose stat sits before the bullet).
        game
        |> add_score(element)
        |> Game.remove_stat(stat_idx)
        |> Game.damage_tile(tx, ty)

      first_try? ->
        check_perpendicular_ricochet(game, stat_idx, stat, tx, ty)

      true ->
        die_against(game, stat_idx, tx, ty)
    end
  end

  # Check the tiles perpendicular to the bullet's direction. ZZT looks
  # at (X + StepY, Y + StepX) first and then the opposite side; a
  # Ricochet on either end reflects the bullet 90° with different sign
  # on each side so it continues away from the reflector.
  defp check_perpendicular_ricochet(game, stat_idx, stat, tx, ty) do
    cw_x = stat.x + stat.step_y
    cw_y = stat.y + stat.step_x
    ccw_x = stat.x - stat.step_y
    ccw_y = stat.y - stat.step_x

    cond do
      ricochet_at?(game, cw_x, cw_y) ->
        game
        |> set_step(stat_idx, -stat.step_y, -stat.step_x)
        |> try_move(stat_idx, false)

      ricochet_at?(game, ccw_x, ccw_y) ->
        game
        |> set_step(stat_idx, stat.step_y, stat.step_x)
        |> try_move(stat_idx, false)

      true ->
        die_against(game, stat_idx, tx, ty)
    end
  end

  # Bullet hit a wall — remove it, then (if the blocker was an Object
  # or Scroll) dispatch `:SHOT` on that stat's program. Ports the tail
  # of ElementBulletTick (ELEMENTS.PAS:380-385). The OOP handler runs
  # inline so the touched object reacts this frame rather than
  # waiting a full cycle.
  defp die_against(game, stat_idx, tx, ty) do
    game = Game.remove_stat(game, stat_idx)

    case Game.tile_at(game, tx, ty) do
      {elem, _} when elem in [@object, @scroll] ->
        case find_stat_at(game.stats, tx, ty) do
          nil -> game
          idx -> game |> Oop.send(-idx, "SHOT") |> Oop.tick(idx)
        end

      _ ->
        game
    end
  end

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s -> s.x == x and s.y == y end)
  end

  defp ricochet_at?(game, x, y) do
    case Map.get(game.tiles, {x, y}) do
      {@ricochet, _} -> true
      _ -> false
    end
  end

  defp set_step(game, stat_idx, sx, sy) do
    stat = Enum.at(game.stats, stat_idx)
    %{game | stats: List.replace_at(game.stats, stat_idx, %Stat{stat | step_x: sx, step_y: sy})}
  end

  # Reference's bullet damage clause: breakables always take the hit,
  # destructibles only if the target is the player OR the shooter was
  # the player (`P1 = 0`).
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
