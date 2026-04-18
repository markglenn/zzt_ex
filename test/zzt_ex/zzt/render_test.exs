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

  test "title_screen? hides the player at stat 0's position" do
    # Fixture places stat 0 at (30, 13); put a Player tile there to match.
    # Row-major index for (30, 13): (13 - 1) * 60 + (30 - 1) = 749.
    tiles = List.replace_at(List.duplicate({0, 0}, 1500), 749, {4, 0x1F})
    {:ok, world} = World.parse(ZztFixture.world(tiles: tiles))
    [board] = world.boards

    normal = Render.rows(board) |> Enum.at(12) |> Enum.at(29)
    hidden = Render.rows(board, title_screen?: true) |> Enum.at(12) |> Enum.at(29)

    # On a playable board we see the smiley face (CP437 0x02 → ☻).
    assert elem(normal, 0) == <<0x263B::utf8>>
    # On the title screen the same cell is blank.
    assert hidden == {" ", 7, 0}
  end

  test "empty tiles ignore residual color bytes and render as pure black" do
    # town.zzt's Tigers building has empty tiles with left-over color 0x73
    # (grey bg / cyan fg). ZZT draws these as black; we must too.
    tiles = List.replace_at(List.duplicate({0, 0}, 1500), 0, {0, 0x73})
    {:ok, world} = World.parse(ZztFixture.world(tiles: tiles))
    [board] = world.boards
    [[cell | _] | _] = Render.rows(board)

    assert cell == {" ", 7, 0}
  end

  test "invisible walls render as blank regardless of stored color" do
    # Invisible with color 0x4F would be a red block if rendered literally.
    tiles = List.replace_at(List.duplicate({0, 0}, 1500), 0, {28, 0x4F})
    {:ok, world} = World.parse(ZztFixture.world(tiles: tiles))
    [board] = world.boards
    [[cell | _] | _] = Render.rows(board)

    assert cell == {" ", 7, 0}
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
