defmodule ZZTEx.Elements.Element do
  defstruct [:element_type, :glyph, :color, walkable: false]

  use Bitwise

  alias ZZTEx.World.Tile

  @type t :: %__MODULE__{
          element_type: element_type_t,
          glyph: arity,
          color: arity,
          walkable: boolean
        }

  @type element_type_t ::
          :empty
          | :board_edge
          | :messenger
          | :monitor
          | :player
          | :ammo
          | :torch
          | :gem
          | :key
          | :door
          | :scroll
          | :passage
          | :duplicator
          | :bomb
          | :energizer
          | :star
          | :clockwise
          | :counter
          | :bullet
          | :water
          | :forest
          | :solid
          | :normal
          | :breakable
          | :boulder
          | :slider_ns
          | :slider_ew
          | :fake
          | :invisible
          | :blink_wall
          | :transporter
          | :line
          | :ricochet
          | :blink_ray_horizontal
          | :bear
          | :ruffian
          | :object
          | :slime
          | :shark
          | :spinning_gun
          | :pusher
          | :lion
          | :tiger
          | :blink_ray_vertical
          | :head
          | :segment
          | :invalid
          | :text_blue
          | :text_green
          | :text_cyan
          | :text_red
          | :text_purple
          | :text_brown
          | :text_black

  @color_element_types [
    :text_blue,
    :text_green,
    :text_cyan,
    :text_red,
    :text_purple,
    :text_brown,
    :text_black
  ]

  def glyph(%__MODULE__{element_type: element_type}, %Tile{color: color}, _)
      when element_type in @color_element_types do
    color
  end

  def glyph(%__MODULE__{element_type: :object}, _, %{p1: glyph}), do: glyph
  def glyph(%__MODULE__{glyph: glyph}, _, _), do: glyph

  def color(%__MODULE__{element_type: element_type, color: color}, _)
      when element_type in @color_element_types,
      do: color

  def color(%__MODULE__{element_type: :empty, color: color}, _), do: color
  def color(%__MODULE__{element_type: :door}, %Tile{color: color}), do: (color &&& 0xF0) + 0xE

  def color(_, %Tile{color: color}), do: color
end
