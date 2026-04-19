defmodule ZztEx.Zzt.AI.Ruffian do
  @moduledoc """
  One-to-one port of `ElementRuffianTick`.

  Resting (`step = {0, 0}`): every tick there's a `(17 - (P2 + 8))/17`
  chance to stand up and start walking. When starting, `P1 >= Random(9)`
  picks a player-seeking direction, otherwise a random one.

  Walking: if aligned with the player on X or Y, re-roll direction with
  `Random(9) <= P1`; then try to step. On a walkable tile, move and roll
  the rest die again — `(P2 + 8) <= Random(17)` — to decide whether to
  pause for the next tick. On the player, attack. Otherwise stop.
  """

  alias ZztEx.Zzt.{Element, Game, Stat}
  alias ZztEx.Zzt.AI.Directions

  @player 4

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    ruffian = Enum.at(game.stats, stat_idx)

    if ruffian.step_x == 0 and ruffian.step_y == 0 do
      maybe_start_walking(game, stat_idx, ruffian)
    else
      walk(game, stat_idx, ruffian)
    end
  end

  defp maybe_start_walking(game, stat_idx, ruffian) do
    # `(P2 + 8) <= Random(17)` — high p2 makes the ruffian stay put longer.
    # Reference just stores the new step here and exits; movement happens
    # on the *next* tick when the walking branch runs. Attempting the
    # move this tick would double the ruffian's speed.
    if ruffian.p2 + 8 <= :rand.uniform(17) - 1 do
      {sx, sy} =
        if ruffian.p1 >= :rand.uniform(9) - 1 do
          Directions.seek(game, ruffian)
        else
          Directions.random_step()
        end

      set_step(game, stat_idx, sx, sy)
    else
      game
    end
  end

  defp walk(game, stat_idx, ruffian) do
    player = Enum.at(game.stats, 0)

    {sx, sy} =
      if (ruffian.y == player.y or ruffian.x == player.x) and
           :rand.uniform(9) - 1 <= ruffian.p1 do
        Directions.seek(game, ruffian)
      else
        {ruffian.step_x, ruffian.step_y}
      end

    game
    |> set_step(stat_idx, sx, sy)
    |> attempt_move(stat_idx)
  end

  defp attempt_move(game, stat_idx) do
    ruffian = Enum.at(game.stats, stat_idx)
    tx = ruffian.x + ruffian.step_x
    ty = ruffian.y + ruffian.step_y

    cond do
      player_at?(game, tx, ty) ->
        Game.collide_with_player(game, stat_idx)

      walkable?(game, tx, ty) ->
        game
        |> Game.move_stat(stat_idx, tx, ty)
        |> maybe_stop(stat_idx, ruffian.p2)

      true ->
        stop_walking(game, stat_idx)
    end
  end

  defp maybe_stop(game, stat_idx, p2) do
    if p2 + 8 <= :rand.uniform(17) - 1 do
      stop_walking(game, stat_idx)
    else
      game
    end
  end

  defp set_step(game, stat_idx, sx, sy) do
    stat = Enum.at(game.stats, stat_idx)
    updated = %Stat{stat | step_x: sx, step_y: sy}
    %{game | stats: List.replace_at(game.stats, stat_idx, updated)}
  end

  defp stop_walking(game, stat_idx), do: set_step(game, stat_idx, 0, 0)

  defp walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element)
    end
  end

  defp player_at?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {@player, _} -> true
      _ -> false
    end
  end
end
