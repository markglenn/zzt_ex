defmodule ZztEx.Zzt.RenderTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.ZztFixture
  alias ZztEx.Zzt.{Render, World}

  test "produces 25 rows of 60 cells" do
    {:ok, world} = World.parse(ZztFixture.world())
    [board] = world.boards
    rows = Render.rows(board)

    assert length(rows) == 25
    assert Enum.all?(rows, &(length(&1) == 60))
  end

  test "empty tile renders as space on black with grey foreground" do
    {:ok, world} = World.parse(ZztFixture.world())
    [board] = world.boards
    [first_row | _] = Render.rows(board)
    {char, _fg, bg} = hd(first_row)

    assert char == " "
    assert bg == 0
  end

  test "decodes foreground and background from the color byte" do
    # Solid (21) with color 0x4F = red bg, white fg
    tiles = List.replace_at(List.duplicate({0, 0}, 1500), 0, {21, 0x4F})
    {:ok, world} = World.parse(ZztFixture.world(tiles: tiles))
    [board] = world.boards
    [[{char, fg, bg} | _] | _] = Render.rows(board)

    assert fg == 15
    assert bg == 4
    # Solid block glyph
    assert char == <<0x2588::utf8>>
  end
end
