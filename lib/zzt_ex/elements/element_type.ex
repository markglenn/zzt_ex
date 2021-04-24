defmodule ZZTEx.Elements.ElementType do
  alias ZZTEx.Elements.Element

  @elements {
    %Element{glyph: 0x20, color: 0x0F, element_type: :empty, walkable: true},
    %Element{glyph: 0x00, color: 0xFF, element_type: :board_edge},
    %Element{glyph: 0x20, color: 0xFF, element_type: :messenger},
    %Element{glyph: 0x20, color: 0x07, element_type: :monitor},
    %Element{glyph: 0x02, color: 0x1F, element_type: :player},
    %Element{glyph: 0x84, color: 0x03, element_type: :ammo},
    %Element{glyph: 0x9D, color: 0x06, element_type: :torch},
    %Element{glyph: 0x04, color: 0xFF, element_type: :gem},
    %Element{glyph: 0x0C, color: 0xFF, element_type: :key},
    %Element{glyph: 0x0A, color: 0xFE, element_type: :door},
    %Element{glyph: 0xE8, color: 0x0F, element_type: :scroll},
    %Element{glyph: 0xF0, color: 0xFE, element_type: :passage},
    %Element{glyph: 0xFA, color: 0x0F, element_type: :duplicator},
    %Element{glyph: 0x0B, color: 0xFF, element_type: :bomb},
    %Element{glyph: 0x7F, color: 0x05, element_type: :energizer},
    %Element{glyph: 0x53, color: 0x0F, element_type: :star},
    %Element{glyph: 0x2F, color: 0xFF, element_type: :clockwise},
    %Element{glyph: 0x5C, color: 0xFF, element_type: :counter},
    %Element{glyph: 0xF8, color: 0x0F, element_type: :bullet},
    %Element{glyph: 0xB0, color: 0xF9, element_type: :water},
    %Element{glyph: 0xB0, color: 0x20, element_type: :forest, walkable: true},
    %Element{glyph: 0xDB, color: 0xFF, element_type: :solid},
    %Element{glyph: 0xB2, color: 0xFF, element_type: :normal},
    %Element{glyph: 0xB1, color: 0xFF, element_type: :breakable},
    %Element{glyph: 0xFE, color: 0xFF, element_type: :boulder},
    %Element{glyph: 0x12, color: 0xFF, element_type: :slider_ns},
    %Element{glyph: 0x1D, color: 0xFF, element_type: :slider_ew},
    %Element{glyph: 0xB2, color: 0xFF, element_type: :fake, walkable: true},
    %Element{glyph: 0xB0, color: 0xFF, element_type: :invisible},
    %Element{glyph: 0xCE, color: 0xFF, element_type: :blink_wall},
    %Element{glyph: 0xC5, color: 0xFF, element_type: :transporter},
    %Element{glyph: 0xCE, color: 0xFF, element_type: :line},
    %Element{glyph: 0x2A, color: 0x0A, element_type: :ricochet},
    %Element{glyph: 0xCD, color: 0xFF, element_type: :blink_ray_horizontal},
    %Element{glyph: 0x99, color: 0x06, element_type: :bear},
    %Element{glyph: 0x05, color: 0x0D, element_type: :ruffian},
    %Element{glyph: 0x02, color: 0xFF, element_type: :object},
    %Element{glyph: 0x2A, color: 0xFF, element_type: :slime},
    %Element{glyph: 0x5E, color: 0x07, element_type: :shark},
    %Element{glyph: 0x18, color: 0xFF, element_type: :spinning_gun},
    %Element{glyph: 0x10, color: 0xFF, element_type: :pusher},
    %Element{glyph: 0xEA, color: 0x0C, element_type: :lion},
    %Element{glyph: 0xE3, color: 0x0B, element_type: :tiger},
    %Element{glyph: 0xBA, color: 0xFF, element_type: :blink_ray_vertical},
    %Element{glyph: 0xE9, color: 0xFF, element_type: :head},
    %Element{glyph: 0x4F, color: 0xFF, element_type: :segment},
    %Element{glyph: 0x20, color: 0xFF, element_type: :invalid},
    %Element{glyph: 0x20, color: 0x1F, element_type: :text_blue},
    %Element{glyph: 0x20, color: 0x2F, element_type: :text_green},
    %Element{glyph: 0x20, color: 0x3F, element_type: :text_cyan},
    %Element{glyph: 0x20, color: 0x4F, element_type: :text_red},
    %Element{glyph: 0x20, color: 0x5F, element_type: :text_purple},
    %Element{glyph: 0x20, color: 0x6F, element_type: :text_brown},
    %Element{glyph: 0x20, color: 0x0F, element_type: :text_black}
  }

  def elements, do: @elements

  @spec element(non_neg_integer) :: ZZTEx.Elements.Element.t()
  def element(index) when is_integer(index), do: elem(@elements, index)
end
