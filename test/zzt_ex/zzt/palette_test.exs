defmodule ZztEx.Zzt.PaletteTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.Palette

  test "splits color byte into fg, bg, blink" do
    assert Palette.decode(0x1F) == {15, 1, false}
    assert Palette.decode(0x0F) == {15, 0, false}
    assert Palette.decode(0x4C) == {12, 4, false}
    # high bit = blink
    assert Palette.decode(0x8F) == {15, 0, true}
  end

  test "returns rgb tuples for the 16-color palette" do
    assert Palette.rgb(0) == {0, 0, 0}
    assert Palette.rgb(15) == {255, 255, 255}
    assert Palette.rgb(4) == {170, 0, 0}
  end

  test "produces CSS hex strings" do
    assert Palette.hex(1) == "#0000aa"
    assert Palette.hex(14) == "#ffff55"
  end
end
