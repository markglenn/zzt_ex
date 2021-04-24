defmodule ZZTEx.World.Tile do
  alias ZZTEx.World.Point

  defstruct [:element, :color]

  @type t :: %__MODULE__{element: arity(), color: arity()}

  @type tiles_t :: %{Point.t() => t()}
end
