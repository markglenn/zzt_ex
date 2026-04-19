defmodule ZztEx.Zzt.AI.Transporter do
  @moduledoc """
  Port of `ElementTransporterMove` / `ElementTransporterTouch`.

  A transporter only fires when pushed along its own mouth direction
  (`step_x / step_y`). It then walks the tiles past itself, skipping
  over anything until it reaches either:

    * a walkable tile (possibly revealed by an in-line push) at the
      current search position — teleport lands there, or
    * a reverse-facing transporter — clears the "valid destination"
      flag so the next tile past it becomes a candidate landing spot.

  The very first tile past the transporter is itself a candidate, so a
  lone transporter with empty space behind it acts as a one-square
  pass-through — matching stock ZZT's editor semantics.
  """

  alias ZztEx.Zzt.{Element, Game}

  @transporter 30

  @doc """
  Try to teleport the tile at `(src_x, src_y)` through the transporter
  at `(src_x + dx, src_y + dy)`. Returns the updated game; if no valid
  destination was found, the input game is returned unchanged.
  """
  @spec try_move(Game.t(), 1..60, 1..25, integer(), integer()) :: Game.t()
  def try_move(%Game{} = game, src_x, src_y, dx, dy) do
    tx = src_x + dx
    ty = src_y + dy

    with idx when not is_nil(idx) <- find_stat_at(game.stats, tx, ty),
         stat <- Enum.at(game.stats, idx),
         true <- stat.step_x == dx and stat.step_y == dy do
      # Search starts at the transporter's own position so the first
      # iteration lands on (X + dx, Y + dy) — the tile immediately
      # past the transporter.
      case search(game, stat.x, stat.y, dx, dy, true) do
        {:found, game, nx, ny} -> Game.element_move(game, src_x, src_y, nx, ny)
        {:not_found, game} -> game
      end
    else
      _ -> game
    end
  end

  # Mirrors the Pascal REPEAT UNTIL loop. `valid?` carries over from
  # the previous iteration and determines whether the newly-reached
  # tile is a candidate landing spot.
  defp search(game, ix, iy, dx, dy, valid?) do
    nix = ix + dx
    niy = iy + dy

    cond do
      not in_bounds?(nix, niy) ->
        {:not_found, game}

      valid? ->
        {elem, _} = Game.tile_at(game, nix, niy)

        game =
          if Element.walkable?(elem) do
            game
          else
            Game.push_tile(game, nix, niy, dx, dy)
          end

        {elem_after, _} = Game.tile_at(game, nix, niy)

        if Element.walkable?(elem_after) do
          {:found, game, nix, niy}
        else
          search(game, nix, niy, dx, dy, reverse_transporter?(game, nix, niy, dx, dy))
        end

      true ->
        search(game, nix, niy, dx, dy, reverse_transporter?(game, nix, niy, dx, dy))
    end
  end

  defp reverse_transporter?(game, x, y, dx, dy) do
    case Game.tile_at(game, x, y) do
      {@transporter, _} ->
        case find_stat_at(game.stats, x, y) do
          nil ->
            false

          idx ->
            ts = Enum.at(game.stats, idx)
            ts.step_x == -dx and ts.step_y == -dy
        end

      _ ->
        false
    end
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s -> s.x == x and s.y == y end)
  end
end
