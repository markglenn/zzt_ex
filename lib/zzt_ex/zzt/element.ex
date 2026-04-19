defmodule ZztEx.Zzt.Element do
  @moduledoc """
  Static metadata for ZZT element IDs.

  ZZT encodes each tile as `{element_id, color}`. This module maps the 54
  standard element IDs to a name, a default CP437 character, and whether the
  element is a "text" element (in which case the color byte is actually the
  glyph to render).

  Some elements (Object, Pusher, Transporter, Conveyor, Bullet, Star, Line,
  BlinkRay, Centipede) have characters that depend on orientation, stat
  parameters, or neighbors. The defaults here are what ZZT uses for a newly
  placed instance; callers that want the "correct" live glyph must look at
  stats or neighbors themselves.
  """

  # {id, name, default_char (CP437 byte), text?}
  @elements [
    {0, :empty, 0x20, false},
    {1, :board_edge, 0x20, false},
    {2, :messenger, 0x20, false},
    {3, :monitor, 0x20, false},
    {4, :player, 0x02, false},
    {5, :ammo, 0x84, false},
    {6, :torch, 0x9D, false},
    {7, :gem, 0x04, false},
    {8, :key, 0x0C, false},
    {9, :door, 0x0A, false},
    {10, :scroll, 0xE8, false},
    {11, :passage, 0xF0, false},
    {12, :duplicator, 0xFA, false},
    {13, :bomb, 0x0B, false},
    {14, :energizer, 0x7F, false},
    {15, :star, 0x53, false},
    {16, :conveyor_cw, 0x2F, false},
    {17, :conveyor_ccw, 0x5C, false},
    {18, :bullet, 0xF8, false},
    {19, :water, 0xB0, false},
    {20, :forest, 0xB0, false},
    {21, :solid, 0xDB, false},
    {22, :normal, 0xB2, false},
    {23, :breakable, 0xB1, false},
    {24, :boulder, 0xFE, false},
    {25, :slider_ns, 0x12, false},
    {26, :slider_ew, 0x1D, false},
    {27, :fake, 0xB2, false},
    # Invisible walls draw as blank until bumped; ZZT reveals them as
    # Normal walls only after the player touches one, so a static renderer
    # must emit an empty cell.
    {28, :invisible, 0x20, false},
    {29, :blink_wall, 0xCE, false},
    {30, :transporter, 0x3C, false},
    {31, :line, 0xCE, false},
    {32, :ricochet, 0x2A, false},
    {33, :blink_ray_h, 0xCD, false},
    {34, :bear, 0x99, false},
    {35, :ruffian, 0x05, false},
    {36, :object, 0x02, false},
    {37, :slime, 0x2A, false},
    {38, :shark, 0x5E, false},
    {39, :spinning_gun, 0x18, false},
    {40, :pusher, 0x10, false},
    {41, :lion, 0xEA, false},
    {42, :tiger, 0xE3, false},
    {43, :blink_ray_v, 0xBA, false},
    {44, :head, 0xE9, false},
    {45, :segment, 0x4F, false},
    {46, :reserved, 0x20, false},
    {47, :text_blue, 0x20, true},
    {48, :text_green, 0x20, true},
    {49, :text_cyan, 0x20, true},
    {50, :text_red, 0x20, true},
    {51, :text_purple, 0x20, true},
    {52, :text_yellow, 0x20, true},
    {53, :text_white, 0x20, true}
  ]

  # Text element background palette indices, in the same order as IDs 47..53.
  @text_backgrounds %{
    47 => 1,
    48 => 2,
    49 => 3,
    50 => 4,
    51 => 5,
    52 => 6,
    53 => 0
  }

  for {id, name, char, text?} <- @elements do
    def name(unquote(id)), do: unquote(name)
    def default_char(unquote(id)), do: unquote(char)
    def text?(unquote(id)), do: unquote(text?)
  end

  # Elements 54+ are not used by stock ZZT but some worlds/editors emit them.
  def name(id) when id in 54..255, do: :unknown
  def default_char(id) when id in 54..255, do: 0x3F
  def text?(id) when id in 54..255, do: false

  # Mirrors `ElementDefs[X].Walkable` — only Empty and Fake. Water
  # (19) is deliberately NOT in this list: the reference's Bullet and
  # Star ticks handle water via explicit `or E_WATER` checks, while
  # every other mover (Lion, Bear, Ruffian, Slime, Centipede, Pusher,
  # Player) treats water as a wall blocked by its touch proc.
  @walkable [0, 27]

  @doc "Whether a monster or the player can step onto `id`."
  @spec walkable?(0..255) :: boolean()
  def walkable?(id), do: id in @walkable

  # ScoreValue in the reference defaults to 0; only monsters pay bounty
  # when the player destroys them (while energized) or a bullet kills them.
  @score_values %{
    34 => 1,
    35 => 2,
    41 => 1,
    42 => 2,
    44 => 1,
    45 => 3
  }

  @doc "Points awarded when `element` is destroyed."
  @spec score_value(0..255) :: non_neg_integer()
  def score_value(id), do: Map.get(@score_values, id, 0)

  # Tiles that shove in a given direction. Mirrors ElementDefs[X].Pushable,
  # plus the two sliders which are only pushable along their own axis.
  @pushable [0, 4, 5, 7, 8, 10, 13, 24, 34, 35, 41, 42]

  @doc """
  Whether a tile can be shoved in the given cardinal direction.
  Sliders are axis-locked: Slider NS only moves on vertical pushes,
  Slider EW only on horizontal. Everything else looks at the static
  Pushable flag.
  """
  @spec pushable?(0..255, integer(), integer()) :: boolean()
  def pushable?(25, _dx, dy) when dy != 0, do: true
  def pushable?(26, dx, _dy) when dx != 0, do: true
  def pushable?(elem, _dx, _dy), do: elem in @pushable

  @doc """
  Static Pushable flag — used by conveyors, which shove in any of eight
  directions and therefore don't honor the slider axis lock.
  """
  @spec pushable?(0..255) :: boolean()
  def pushable?(elem), do: elem in @pushable

  # Destructible tiles get crushed when something pushes them into a
  # wall. Matches ElementDefs[X].Destructible.
  @destructible [4, 7, 18, 34, 35, 41, 42, 44, 45]

  @doc "Whether `element` can be destroyed by a pushed tile."
  @spec destructible?(0..255) :: boolean()
  def destructible?(id), do: id in @destructible

  @doc """
  Background palette index for a text element (47..53), or `nil` otherwise.

  Text elements render their glyph (stored in the color byte) using white
  foreground over a fixed background color keyed off the element ID.
  """
  @spec text_background(0..255) :: 0..15 | nil
  def text_background(id), do: Map.get(@text_backgrounds, id)

  @doc """
  List of `{id, name, default_char}` for all stock elements, useful for docs
  and debugging.
  """
  @spec all() :: [{0..53, atom(), 0..255}]
  def all do
    for {id, name, char, _text?} <- unquote(Macro.escape(@elements)), do: {id, name, char}
  end
end
