defmodule ZztEx.Zzt.AI.Star do
  @moduledoc """
  One-to-one port of `ElementStarTick`. Stars are persistent projectiles
  spawned by Tigers or SpinningGuns with `P2 := 100` — they live for up
  to 100 ticks, chasing the player along axis-aligned directions.

      P2 -= 1
      if P2 <= 0: remove
      elsif P2 mod 2 == 0:
        step = CalcDirectionSeek toward the player
        target = tile at (X+step)
        if player or breakable: BoardAttack (damage both, star dies)
        elsif not walkable: try push
        if walkable or water: move
      else: just exist (draw) this tick

  Stars ignore the source-match rule — they damage any player or
  breakable they hit, regardless of who fired them.
  """

  alias ZztEx.Zzt.{Element, Game, Stat}
  alias ZztEx.Zzt.AI.Directions

  @water 19
  @player 4
  @breakable 23

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    p2 = stat.p2 - 1

    cond do
      p2 <= 0 ->
        Game.remove_stat(game, stat_idx)

      rem(p2, 2) == 0 ->
        game
        |> update_p2(stat_idx, p2)
        |> step(stat_idx)

      true ->
        update_p2(game, stat_idx, p2)
    end
  end

  defp update_p2(game, stat_idx, new_p2) do
    stat = Enum.at(game.stats, stat_idx)
    %{game | stats: List.replace_at(game.stats, stat_idx, %Stat{stat | p2: new_p2})}
  end

  defp step(game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    {dx, dy} = Directions.seek(game, stat)

    # Store the new step so the renderer picks up the direction.
    game =
      %{
        game
        | stats: List.replace_at(game.stats, stat_idx, %Stat{stat | step_x: dx, step_y: dy})
      }

    tx = stat.x + dx
    ty = stat.y + dy

    case Map.get(game.tiles, {tx, ty}) do
      nil ->
        game

      {@player, _} ->
        Game.collide_with_player(game, stat_idx)

      {@breakable, _} ->
        game |> Game.damage_tile(tx, ty) |> Game.remove_stat(stat_idx)

      {element, _} ->
        game = if Element.walkable?(element), do: game, else: Game.push_tile(game, tx, ty, dx, dy)

        {after_elem, _} = Map.fetch!(game.tiles, {tx, ty})

        if Element.walkable?(after_elem) or after_elem == @water do
          Game.move_stat(game, stat_idx, tx, ty)
        else
          game
        end
    end
  end
end
