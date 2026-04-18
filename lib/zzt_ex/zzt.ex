defmodule ZztEx.Zzt do
  @moduledoc """
  ZZT world file parsing and runtime.

  ZZT is Tim Sweeney's 1991 DOS text-mode adventure game. A `.zzt` file is a
  little-endian binary: a 512-byte world header followed by a sequence of
  length-prefixed boards. Each board is a 60x25 grid of tiles, a small set of
  scalar properties, and an array of "stats" (entities with position, cycle,
  and optionally ZZT-OOP bytecode).

  This top-level module is a namespace only; see `ZztEx.Zzt.World` for the
  parser entry point.
  """
end
