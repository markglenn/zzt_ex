defmodule ZztEx.Zzt.AI.Directions do
  @moduledoc """
  Shared direction helpers, ported from `CalcDirectionRnd` and
  `CalcDirectionSeek` in `reconstruction-of-zzt/SRC/GAME.PAS`.
  """

  alias ZztEx.Zzt.Game

  @type step :: {-1 | 0 | 1, -1 | 0 | 1}

  @doc """
  Pascal:

      deltaX := Random(3) - 1;
      if deltaX = 0 then
        deltaY := Random(2) * 2 - 1
      else
        deltaY := 0;

  Produces a cardinal step with a horizontal bias — 1/3 west, 1/3 east,
  1/6 north, 1/6 south — rather than uniform 1/4 per direction.
  """
  @spec random_step() :: step()
  def random_step do
    dx = :rand.uniform(3) - 2

    if dx == 0 do
      {0, :rand.uniform(2) * 2 - 3}
    else
      {dx, 0}
    end
  end

  @doc """
  Pascal port of `CalcDirectionSeek(x, y, deltaX, deltaY)`. Rolls a 1-in-2
  (or takes it when already on the player's row) to move horizontally;
  otherwise moves vertically. Inverts the resulting step when the player
  is energized so the source flees instead of chasing.
  """
  @spec seek(Game.t(), %{x: integer(), y: integer()}) :: step()
  def seek(%Game{} = game, %{x: sx, y: sy}) do
    player = Enum.at(game.stats, 0)

    dx =
      if :rand.uniform(2) == 1 or player.y == sy do
        signum(player.x - sx)
      else
        0
      end

    dy = if dx == 0, do: signum(player.y - sy), else: 0

    if Game.energized?(game), do: {-dx, -dy}, else: {dx, dy}
  end

  @doc "Sign of an integer (-1, 0, or 1)."
  @spec signum(integer()) :: -1 | 0 | 1
  def signum(0), do: 0
  def signum(n) when n > 0, do: 1
  def signum(_), do: -1
end
