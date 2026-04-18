defmodule ZztEx.Zzt.AI.Lion do
  @moduledoc """
  Lion tick behavior, ported from ZZT's `ElementLionTick`.

  Each lion picks a direction then either moves into that tile, attacks
  the player if it's there, or does nothing if blocked:

    1. With probability `p1 / 10`, seek the player; otherwise pick a
       random cardinal direction.
    2. If the player is energized, invert the chosen direction — lions
       run away from an energized player.
    3. Walk into the tile if it's `Element.walkable?/1`; attack if it's
       the player; otherwise stay put.

  On attacking the player, the lion dies. Without an energizer the
  player takes 10 damage; with one, the player is unharmed and the lion
  simply dies on contact.
  """

  alias ZztEx.Zzt.{Element, Game}

  @player_damage 10

  @doc """
  Run one tick for the lion at `stat_idx`. Returns the updated game.
  """
  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    player = Enum.at(game.stats, 0)

    {dx, dy} = direction(stat, player, Game.energized?(game))
    tx = stat.x + dx
    ty = stat.y + dy

    cond do
      not in_bounds?(tx, ty) ->
        game

      tx == player.x and ty == player.y ->
        collide_with_player(game, stat_idx)

      walkable_target?(game, tx, ty) ->
        Game.move_stat(game, stat_idx, tx, ty)

      true ->
        game
    end
  end

  # ZZT: `if Random(0, 9) < p1 then seek else random`. p1 is a 0..8
  # "intelligence" stored in the stat; higher means more likely to chase.
  defp direction(stat, player, energized?) do
    {dx, dy} =
      if :rand.uniform(10) - 1 < stat.p1 do
        seek(stat, player)
      else
        random_step()
      end

    if energized?, do: {-dx, -dy}, else: {dx, dy}
  end

  # Axis-aligned seek: roll a 1-in-3 to force horizontal (or take it when
  # already at the player's row), otherwise move vertically.
  defp seek(%{x: sx, y: sy}, %{x: px, y: py}) do
    horizontal? = :rand.uniform(3) == 1 or py == sy

    dx = if horizontal?, do: signum(px - sx), else: 0
    dy = if dx == 0, do: signum(py - sy), else: 0

    {dx, dy}
  end

  defp random_step do
    case :rand.uniform(4) do
      1 -> {-1, 0}
      2 -> {1, 0}
      3 -> {0, -1}
      4 -> {0, 1}
    end
  end

  defp signum(0), do: 0
  defp signum(n) when n > 0, do: 1
  defp signum(_), do: -1

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp walkable_target?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {element, _color} -> Element.walkable?(element)
    end
  end

  defp collide_with_player(game, lion_idx) do
    if Game.energized?(game) do
      Game.remove_stat(game, lion_idx)
    else
      game
      |> Game.damage_player(@player_damage)
      |> Game.remove_stat(lion_idx)
    end
  end
end
