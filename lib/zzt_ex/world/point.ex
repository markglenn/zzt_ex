defmodule ZZTEx.World.Point do
  @type t :: {integer(), integer()}

  @spec add(t, t) :: t
  def add({x1, y1}, {x2, y2}), do: {x1 + x2, y1 + y2}
end
