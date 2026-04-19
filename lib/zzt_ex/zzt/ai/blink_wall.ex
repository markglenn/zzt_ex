defmodule ZztEx.Zzt.AI.BlinkWall do
  @moduledoc """
  Port of `ElementBlinkWallTick`.

  Blink walls flash a beam of Blink Ray tiles along their step vector.
  A single `P3` counter encodes the phase:

    * `P3 = 0` — freshly placed. Next tick sets `P3 = P1 + 1` so `P1`
      acts as a startup delay.
    * `P3 = 1` — fire. Either retract an existing beam of our own
      color, or lay a new one down. Either way, `P3` resets to
      `P2 * 2 + 1` so the cadence is `P2 * 2` ticks between flips.
    * otherwise — decrement.

  New-beam sweep: every tile along the step vector gets inspected.
  Destructibles are damaged in place, the player is shoved aside (or
  killed if there's no escape square), empty cells become ray tiles,
  and anything else terminates the sweep.
  """

  alias ZztEx.Zzt.{Element, Game, Stat}

  @empty 0
  @player 4
  @blink_ray_ew 33
  @blink_ray_ns 43

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)

    # First-time init: P3 = 0 means "fresh". P1 carries the startup delay.
    stat = if stat.p3 == 0, do: %Stat{stat | p3: stat.p1 + 1}, else: stat

    cond do
      stat.p3 != 1 ->
        write_stat(game, stat_idx, %Stat{stat | p3: stat.p3 - 1})

      true ->
        fire(game, stat_idx, stat)
    end
  end

  defp fire(game, stat_idx, stat) do
    ray_elem = if stat.step_x != 0, do: @blink_ray_ew, else: @blink_ray_ns
    {_, wall_color} = Map.fetch!(game.tiles, {stat.x, stat.y})

    {game, retracted?, next_x, next_y} =
      retract(game, stat.x + stat.step_x, stat.y + stat.step_y, stat.step_x, stat.step_y,
        ray_elem: ray_elem,
        wall_color: wall_color
      )

    game =
      if retracted? do
        game
      else
        # No existing beam to retract — lay down a fresh one starting
        # at (next_x, next_y) == (X + step, Y + step).
        emit(game, stat_idx, next_x, next_y, stat.step_x, stat.step_y,
          ray_elem: ray_elem,
          wall_color: wall_color
        )
      end

    # Re-read the stat (may have shifted if emit damaged stats at lower indices).
    stat_idx = refind_stat_idx(game, stat.x, stat.y) || stat_idx
    stat = Enum.at(game.stats, stat_idx)
    write_stat(game, stat_idx, %Stat{stat | p3: stat.p2 * 2 + 1})
  end

  # Walk along (dx, dy) clearing ray tiles that match our color. Returns
  # `{game, retracted?, next_x, next_y}` where `next_x/y` is where the
  # sweep halted (the starting tile if nothing was retracted).
  defp retract(game, ix, iy, dx, dy, opts) do
    ray_elem = Keyword.fetch!(opts, :ray_elem)
    wall_color = Keyword.fetch!(opts, :wall_color)

    do_retract(game, ix, iy, dx, dy, ray_elem, wall_color, false)
  end

  defp do_retract(game, ix, iy, dx, dy, ray_elem, wall_color, retracted?) do
    case Game.tile_at(game, ix, iy) do
      {^ray_elem, ^wall_color} ->
        tiles = Map.put(game.tiles, {ix, iy}, {@empty, 0x0F})
        do_retract(%{game | tiles: tiles}, ix + dx, iy + dy, dx, dy, ray_elem, wall_color, true)

      _ ->
        {game, retracted?, ix, iy}
    end
  end

  # Lay down a new beam. Iterate along (dx, dy) from (ix, iy) damaging
  # destructibles, bumping the player, and converting empty tiles to
  # ray — stop as soon as we hit an obstacle.
  defp emit(game, _stat_idx, ix, iy, dx, dy, opts) do
    ray_elem = Keyword.fetch!(opts, :ray_elem)
    wall_color = Keyword.fetch!(opts, :wall_color)

    do_emit(game, ix, iy, dx, dy, ray_elem, wall_color)
  end

  defp do_emit(game, ix, iy, dx, dy, ray_elem, wall_color) do
    if not in_bounds?(ix, iy) do
      game
    else
      game = damage_if_destructible(game, ix, iy)
      {game, halted?} = nudge_or_kill_player(game, ix, iy, dx, dy)

      cond do
        halted? ->
          game

        match?({@empty, _}, Game.tile_at(game, ix, iy)) ->
          tiles = Map.put(game.tiles, {ix, iy}, {ray_elem, wall_color})
          do_emit(%{game | tiles: tiles}, ix + dx, iy + dy, dx, dy, ray_elem, wall_color)

        true ->
          game
      end
    end
  end

  defp damage_if_destructible(game, ix, iy) do
    case Game.tile_at(game, ix, iy) do
      {elem, _} when elem != @empty ->
        if Element.destructible?(elem), do: Game.damage_tile(game, ix, iy), else: game

      _ ->
        game
    end
  end

  # Player in the ray path: try to push them perpendicular, else kill.
  # Returns `{game, halted?}` — halted? true means the player was killed
  # so the sweep terminates on this tile.
  defp nudge_or_kill_player(game, ix, iy, dx, dy) do
    case Game.tile_at(game, ix, iy) do
      {@player, _} ->
        {game, moved?} = try_shove_player(game, ix, iy, dx, dy)

        if moved? do
          {game, false}
        else
          # No escape — drain health to zero.
          player_state = %{game.player | health: 0}
          {%{game | player: player_state}, true}
        end

      _ ->
        {game, false}
    end
  end

  # For a horizontal ray push the player north or south; for a vertical
  # ray push east or west. Mirrors the (slightly buggy) reference path.
  defp try_shove_player(game, ix, iy, dx, _dy) when dx != 0 do
    cond do
      empty?(game, ix, iy - 1) -> {Game.move_stat(game, 0, ix, iy - 1), true}
      empty?(game, ix, iy + 1) -> {Game.move_stat(game, 0, ix, iy + 1), true}
      true -> {game, false}
    end
  end

  defp try_shove_player(game, ix, iy, _dx, _dy) do
    cond do
      empty?(game, ix + 1, iy) -> {Game.move_stat(game, 0, ix + 1, iy), true}
      empty?(game, ix - 1, iy) -> {Game.move_stat(game, 0, ix - 1, iy), true}
      true -> {game, false}
    end
  end

  defp empty?(game, x, y) do
    match?({@empty, _}, Game.tile_at(game, x, y))
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp write_stat(game, stat_idx, stat) do
    %{game | stats: List.replace_at(game.stats, stat_idx, stat)}
  end

  defp refind_stat_idx(game, x, y) do
    Enum.find_index(game.stats, fn s -> s.x == x and s.y == y end)
  end
end
