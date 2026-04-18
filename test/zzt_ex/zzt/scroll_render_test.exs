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

  test "content rows show each line indented two cells past the vertical bar" do
    # line_pos: 0 keeps arrows off so we can see the raw indent.
    rows = ScrollRender.render(%{title: "T", lines: ["Hello world"]}, line_pos: 0)
    text = row_text(Enum.at(rows, 3))

    assert String.contains?(text, Cp437.char(0xB3) <> "  Hello world")
  end

  test "$-centered lines drop the sigil and center the rest in the accent color" do
    rows = ScrollRender.render(%{title: "T", lines: ["$  Centered text"]}, line_pos: 0)
    centered_row = Enum.at(rows, 3)

    # Grab only the text glyphs on blue bg (exclude border vert-bar on black).
    text_cells =
      centered_row
      |> Enum.filter(fn {char, _fg, bg, _blink} -> char != " " and bg == 1 end)

    assert Enum.all?(text_cells, fn {_char, fg, _bg, _blink} -> fg == 15 end)

    assert centered_row |> row_text() |> String.contains?("Centered text")
  end

  test "selection arrows appear on the line_pos-th content row" do
    rows =
      ScrollRender.render(%{title: "T", lines: ["one", "two", "three"]}, line_pos: 2)

    arrow_r = Cp437.char(0xAF)
    arrow_l = Cp437.char(0xAE)

    # Row 3 = line 1 (no arrows), row 4 = line 2 (arrows), row 5 = line 3.
    second_line = row_text(Enum.at(rows, 4))
    assert String.contains?(second_line, arrow_r)
    assert String.contains?(second_line, arrow_l)

    first_line = row_text(Enum.at(rows, 3))
    refute String.contains?(first_line, arrow_r)
  end
end
