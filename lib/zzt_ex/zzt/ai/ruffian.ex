defmodule ZztEx.Zzt.AI.Ruffian do
  @moduledoc """
  Ruffian tick behavior, ported from ZZT's `ElementRuffianTick`.

  Ruffians alternate between resting and walking. `p1` is chase intensity
  (0-8) and `p2` is resting tendency (0-8):

    * When stationary (`step == {0, 0}`), roll a d18 — if it clears
      `p2 + 8`, pick a random direction and start walking.
    * When walking, if the ruffian is aligned with the player on a row
      or column, roll `p1 / 10` to redirect the step toward the player.
    * Try to move one step; attack the player on contact, stop on blocked.
  """

  alias ZztEx.Zzt.{Element, Game, Stat}
  alias ZztEx.Zzt.AI.Directions

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    ruffian = Enum.at(game.stats, stat_idx)

    if ruffian.step_x == 0 and ruffian.step_y == 0 do
      maybe_start_walking(game, stat_idx, ruffian)
    else
      redirect_and_move(game, stat_idx, ruffian)
    end
  end

  defp maybe_start_walking(game, stat_idx, ruffian) do
    if :rand.uniform(18) - 1 >= ruffian.p2 + 8 do
      {sx, sy} = Directions.random_step()
      game |> set_step(stat_idx, sx, sy) |> attempt_move(stat_idx)
    else
      game
    end
  end

  defp redirect_and_move(game, stat_idx, ruffian) do
    player = Enum.at(game.stats, 0)

    {sx, sy} =
      cond do
        ruffian.y == player.y and :rand.uniform(10) - 1 < ruffian.p1 ->
          {Directions.signum(player.x - ruffian.x), 0}

        ruffian.x == player.x and :rand.uniform(10) - 1 < ruffian.p1 ->
          {0, Directions.signum(player.y - ruffian.y)}

        true ->
          {ruffian.step_x, ruffian.step_y}
      end

    game |> set_step(stat_idx, sx, sy) |> attempt_move(stat_idx)
  end

  defp attempt_move(game, stat_idx) do
    ruffian = Enum.at(game.stats, stat_idx)
    player = Enum.at(game.stats, 0)
    tx = ruffian.x + ruffian.step_x
    ty = ruffian.y + ruffian.step_y

    cond do
      not in_bounds?(tx, ty) -> stop_walking(game, stat_idx)
      tx == player.x and ty == player.y -> Game.collide_with_player(game, stat_idx)
      walkable?(game, tx, ty) -> Game.move_stat(game, stat_idx, tx, ty)
      true -> stop_walking(game, stat_idx)
    end
  end

  defp set_step(game, stat_idx, sx, sy) do
    stat = Enum.at(game.stats, stat_idx)
    updated = %Stat{stat | step_x: sx, step_y: sy}
    %{game | stats: List.replace_at(game.stats, stat_idx, updated)}
  end

  defp stop_walking(game, stat_idx), do: set_step(game, stat_idx, 0, 0)

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element)
    end
  end
end
