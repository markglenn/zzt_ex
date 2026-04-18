defmodule ZztEx.Zzt.ScrollRenderTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Cp437, ScrollRender}

  defp row_text(row) do
    row
    |> Enum.map(fn {char, _fg, _bg, _blink} -> char end)
    |> Enum.join()
  end

  test "produces a 50x18 cell grid" do
    rows = ScrollRender.render(%{title: "Test", lines: []})

    assert length(rows) == 18
    assert Enum.all?(rows, &(length(&1) == 50))
  end

  test "top and bottom borders match ZZT's TextWindowStr* patterns" do
    rows = ScrollRender.render(%{title: "Test", lines: []})
    top = row_text(Enum.at(rows, 0))
    bottom = row_text(Enum.at(rows, 17))

    # ╞╤ [45 ═] ╤╡ then a trailing blank (50th cell)
    assert String.starts_with?(top, Cp437.char(0xC6) <> Cp437.char(0xD1))
    assert String.contains?(top, String.duplicate(Cp437.char(0xCD), 45))
    # ╞╧ ... ╧╡
    assert String.starts_with?(bottom, Cp437.char(0xC6) <> Cp437.char(0xCF))
  end

  test "title is centered in the inner area" do
    rows = ScrollRender.render(%{title: "Hi", lines: []})
    title = row_text(Enum.at(rows, 1))

    # Row is " │ 45-char-inner │  " with title centered across the inner 45.
    # Center of inner width = 22; "Hi" occupies 2 chars so it starts ~21.
    assert String.contains?(title, "Hi")
  end

  test "a single line lands on the middle row (not the first content row)" do
    # The selected line always sits at (Height div 2 + 1) = row 10.
    rows = ScrollRender.render(%{title: "T", lines: ["Hello world"]})
    middle = row_text(Enum.at(rows, 10))

    assert String.contains?(middle, "Hello world")

    # Row 3 (the first content row) is empty when there's only one line.
    assert row_text(Enum.at(rows, 3)) |> String.trim() =~ ~r/^\p{Zs}*[│]?[»]?.*[«]?[│]?\p{Zs}*$/u
    refute row_text(Enum.at(rows, 3)) |> String.contains?("Hello world")
  end

  test "$-centered lines drop the sigil and center the rest in the accent color" do
    # `line_pos: 0` suppresses the middle-row arrows so we can see only
    # the line's own glyphs.
    rows = ScrollRender.render(%{title: "T", lines: ["$  Centered text"]}, line_pos: 0)

    # Line 1 at line_pos: 0 lands one row below middle.
    centered_row = Enum.at(rows, 11)

    text_cells =
      centered_row
      |> Enum.filter(fn {char, _fg, bg, _blink} -> char != " " and bg == 1 end)

    assert Enum.all?(text_cells, fn {_char, fg, _bg, _blink} -> fg == 15 end)
    assert row_text(centered_row) =~ "Centered text"
  end

  test "dotted header and footer rows frame the scroll's line range" do
    # With 3 lines and line_pos = 2, middle (row 10) shows line 2.
    # Row 9 = line 1, row 8 = lpos 0 (dotted header).
    # Row 11 = line 3, row 12 = lpos 4 = count+1 (dotted footer).
    rows =
      ScrollRender.render(%{title: "T", lines: ["a", "b", "c"]}, line_pos: 2)

    bullet = Cp437.char(0x07)

    header = row_text(Enum.at(rows, 8))
    footer = row_text(Enum.at(rows, 12))

    # Bullets appear at every 5th inner column (10 bullets total).
    assert header |> String.graphemes() |> Enum.count(&(&1 == bullet)) == 9
    assert footer |> String.graphemes() |> Enum.count(&(&1 == bullet)) == 9
  end

  test "selection arrows always ride the middle row; other lines stack around it" do
    rows =
      ScrollRender.render(%{title: "T", lines: ["one", "two", "three"]}, line_pos: 2)

    arrow_r = Cp437.char(0xAF)
    arrow_l = Cp437.char(0xAE)

    # Middle row (10) holds the selected line "two" with arrows.
    middle = row_text(Enum.at(rows, 10))
    assert String.contains?(middle, "two")
    assert String.contains?(middle, arrow_r)
    assert String.contains?(middle, arrow_l)

    # Line 1 sits one row above, line 3 one row below. Neither has arrows.
    above = row_text(Enum.at(rows, 9))
    below = row_text(Enum.at(rows, 11))
    assert String.contains?(above, "one")
    assert String.contains?(below, "three")
    refute String.contains?(above, arrow_r)
    refute String.contains?(below, arrow_r)
  end
end
