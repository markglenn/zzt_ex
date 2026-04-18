defmodule ZztEx.Zzt.AI.Directions do
  @moduledoc """
  Shared direction helpers used by monster AI.

  ZZT's movement code is mostly cardinal: step vectors are always one of
  `{-1, 0}`, `{1, 0}`, `{0, -1}`, `{0, 1}`, or `{0, 0}`. Monsters pick
  directions either randomly or by seeking the player with a 1-in-3
  horizontal bias.
  """

  @type step :: {-1 | 0 | 1, -1 | 0 | 1}

  @doc "One random cardinal step."
  @spec random_step() :: step()
  def random_step do
    case :rand.uniform(4) do
      1 -> {-1, 0}
      2 -> {1, 0}
      3 -> {0, -1}
      4 -> {0, 1}
    end
  end

  @doc """
  Axis-aligned seek toward `target` from `source`. Takes a horizontal
  step on a 1-in-3 roll (or when already on the target's row); otherwise
  steps vertically. Matches ZZT's `CalcDirectionSeek`.
  """
  @spec seek(%{x: integer(), y: integer()}, %{x: integer(), y: integer()}) :: step()
  def seek(%{x: sx, y: sy}, %{x: tx, y: ty}) do
    horizontal? = :rand.uniform(3) == 1 or ty == sy
    dx = if horizontal?, do: signum(tx - sx), else: 0
    dy = if dx == 0, do: signum(ty - sy), else: 0
    {dx, dy}
  end

  @doc "Sign of an integer (-1, 0, or 1)."
  @spec signum(integer()) :: -1 | 0 | 1
  def signum(0), do: 0
  def signum(n) when n > 0, do: 1
  def signum(_), do: -1
end
