defmodule ZztEx.Zzt.AI.Bear do
  @moduledoc """
  One-to-one port of `ElementBearTick`.

      if X <> Player.X and Difference(Y, Player.Y) <= (8 - P1):
        deltaX := Signum(Player.X - X); deltaY := 0
      else if Difference(X, Player.X) <= (8 - P1):
        deltaY := Signum(Player.Y - Y); deltaX := 0
      else:
        deltaX, deltaY := 0, 0

      if Walkable:        MoveStat
      else if Player or Breakable:  BoardAttack

  `p1` is "sensitivity": `8 - p1` is the detection range, so a lower `p1`
  makes the bear close from farther away. Bears are kamikaze — attacking
  either the player or a breakable wall kills the bear (via `BoardAttack`
  → `DamageStat` on the attacker) and destroys the target tile.
  """

  alias ZztEx.Zzt.{Element, Game}
  alias ZztEx.Zzt.AI.Directions

  @player 4
  @breakable 23

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    bear = Enum.at(game.stats, stat_idx)
    player = Enum.at(game.stats, 0)
    sensitivity = 8 - bear.p1

    {dx, dy} =
      cond do
        bear.x != player.x and abs(player.y - bear.y) <= sensitivity ->
          {Directions.signum(player.x - bear.x), 0}

        abs(player.x - bear.x) <= sensitivity ->
          {0, Directions.signum(player.y - bear.y)}

        true ->
          {0, 0}
      end

    tx = bear.x + dx
    ty = bear.y + dy

    cond do
      dx == 0 and dy == 0 -> game
      walkable?(game, tx, ty) -> Game.move_stat(game, stat_idx, tx, ty)
      player_at?(game, tx, ty) -> Game.collide_with_player(game, stat_idx)
      breakable_at?(game, tx, ty) -> attack_breakable(game, stat_idx, tx, ty)
      true -> game
    end
  end

  # Reference's BoardAttack on a breakable: the attacker dies and the
  # breakable's tile becomes empty.
  defp attack_breakable(game, bear_idx, x, y) do
    game
    |> Game.remove_stat(bear_idx)
    |> destroy_tile(x, y)
  end

  defp destroy_tile(game, x, y) do
    %{game | tiles: Map.put(game.tiles, {x, y}, {0, 0x0F})}
  end

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

  defp breakable_at?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {@breakable, _} -> true
      _ -> false
    end
  end
end
