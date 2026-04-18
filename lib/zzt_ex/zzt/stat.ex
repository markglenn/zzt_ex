defmodule ZztEx.Zzt.Stat do
  @moduledoc """
  A ZZT "stat" — an active entity on a board.

  Stat 0 is always the player. Other stats are monsters, scripted objects,
  pushers, bullets, centipede segments, etc. A stat carries a position, step
  vector, cycle (update frequency), three generic parameter bytes, follower
  and leader references (for centipedes), the element/color that is *under*
  this stat (revealed when it moves), and optionally a ZZT-OOP bytecode body.
  """

  @enforce_keys [:x, :y]
  defstruct x: 0,
            y: 0,
            step_x: 0,
            step_y: 0,
            cycle: 0,
            p1: 0,
            p2: 0,
            p3: 0,
            follower: -1,
            leader: -1,
            under_element: 0,
            under_color: 0,
            instruction: 0,
            bound: 0,
            code: <<>>

  @type t :: %__MODULE__{
          x: 1..60,
          y: 1..25,
          step_x: integer(),
          step_y: integer(),
          cycle: integer(),
          p1: 0..255,
          p2: 0..255,
          p3: 0..255,
          follower: integer(),
          leader: integer(),
          under_element: 0..255,
          under_color: 0..255,
          instruction: integer(),
          bound: integer(),
          code: binary()
        }

  @header_size 33

  @doc """
  Parse a single stat entry (header + optional code body) from the head of
  `binary`. Returns `{stat, rest}`.

  The on-disk layout is a 33-byte header followed by `max(bound, 0)` bytes
  of ZZT-OOP code. A negative `bound` means "my code is whichever stat has
  ID `-bound`" — in that case no code bytes follow the header.
  """
  @spec parse(binary()) :: {t(), binary()}
  def parse(<<
        x,
        y,
        step_x::little-signed-16,
        step_y::little-signed-16,
        cycle::little-signed-16,
        p1,
        p2,
        p3,
        follower::little-signed-16,
        leader::little-signed-16,
        under_element,
        under_color,
        _pointer::little-32,
        instruction::little-signed-16,
        bound::little-signed-16,
        _unused::binary-size(8),
        rest::binary
      >>) do
    code_size = if bound > 0, do: bound, else: 0
    <<code::binary-size(code_size), after_code::binary>> = rest

    stat = %__MODULE__{
      x: x,
      y: y,
      step_x: step_x,
      step_y: step_y,
      cycle: cycle,
      p1: p1,
      p2: p2,
      p3: p3,
      follower: follower,
      leader: leader,
      under_element: under_element,
      under_color: under_color,
      instruction: instruction,
      bound: bound,
      code: code
    }

    {stat, after_code}
  end

  @doc "Size in bytes of a stat's on-disk header (before any code body)."
  def header_size, do: @header_size
end
