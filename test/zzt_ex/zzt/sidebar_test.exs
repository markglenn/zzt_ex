defmodule ZztEx.Zzt.SidebarTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Sidebar, World}

  defp world(overrides \\ []) do
    struct(%World{}, Enum.into(overrides, %{}))
  end

  defp cell_string(row) do
    row
    |> Enum.map(fn {char, _fg, _bg, _blink} -> char end)
    |> Enum.join()
  end

  test "is exactly 20 columns by 25 rows" do
    rows = Sidebar.rows(world())

    assert length(rows) == Sidebar.height()
    assert length(rows) == 25
    assert Enum.all?(rows, &(length(&1) == Sidebar.width()))
    assert Enum.all?(rows, &(length(&1) == 20))
  end

  test "column 1 is always blank blue padding" do
    # Only col 1 is reliably blank on every row; row 19 paints " Shift " at
    # col 2, so the broader padding claim doesn't hold for every row.
    rows = Sidebar.rows(world())

    for {row, row_idx} <- Enum.with_index(rows) do
      {char, _fg, bg, _blink} = Enum.at(row, 0)
      assert {row_idx, char, bg} == {row_idx, " ", 1}
    end
  end

  test "top three rows are dash, title, dash matching GameDrawSidebar" do
    rows = Sidebar.rows(world())

    # Reference writes dashes at rows 0 and 2 and "ZZT" at row 1.
    assert cell_string(Enum.at(rows, 0)) =~ "- - - - -"
    assert cell_string(Enum.at(rows, 1)) =~ "ZZT"
    assert cell_string(Enum.at(rows, 2)) =~ "- - - - -"

    # "ZZT" title cell is black-on-grey per VideoWriteText(62, 1, $70, ...).
    {_char, fg, bg, _blink} = Enum.at(Enum.at(rows, 1), 8)
    assert {fg, bg} == {0, 7}
  end

  test "ammo and gem icons use bright cyan (fg 11) like the reference" do
    rows = Sidebar.rows(world())
    # Ammo row is after Health; Gem row after Torches.
    {_char, ammo_fg, _bg, _blink} = Enum.at(Enum.at(rows, 8), 2)
    {_char, gem_fg, _bg, _blink} = Enum.at(Enum.at(rows, 10), 2)

    assert ammo_fg == 11
    assert gem_fg == 11
  end

  test "health row renders smiley at col 3 plus yellow 'Health:93'" do
    rows = Sidebar.rows(world(health: 93))
    # Layout mirrors GameDrawSidebar: dash/title/dash, four blanks,
    # then stats start at row 7.
    health_row = Enum.at(rows, 7)
    text = cell_string(health_row)

    assert text =~ "Health:93"
    # Smiley glyph at col 3 (idx 2), CP437 0x02 → ☻ U+263B.
    {char, fg, bg, _blink} = Enum.at(health_row, 2)
    assert char == <<0x263B::utf8>>
    assert {fg, bg} == {15, 1}

    # "Health:" right-aligned with colon at col 12 → label at col 6 (idx 5).
    {label_char, label_fg, _bg, _blink} = Enum.at(health_row, 5)
    assert label_char == "H"
    assert label_fg == 14

    # Value at col 13 (idx 12) is yellow.
    {value_char, value_fg, _bg, _blink} = Enum.at(health_row, 12)
    assert value_char == "9"
    assert value_fg == 14
  end

  test "score row has the label right-aligned so the colon lands at col 12" do
    rows = Sidebar.rows(world(score: 30))
    text = cell_string(Enum.at(rows, 11))

    # "Score:" starts at col 7 (idx 6) so the ':' lands at col 12 (idx 11).
    assert String.slice(text, 6, 6) == "Score:"
    # Value "30" starts at col 13 (idx 12), right after the colon.
    assert String.slice(text, 12, 2) == "30"
  end

  test "owned keys render as colored ♀ glyphs starting at col 13" do
    rows = Sidebar.rows(world(keys: [true, false, false, true, false, false, false]))
    keys_row = Enum.at(rows, 12)

    # Slot 0 (blue key) at col 13 (idx 12), slot 3 (red key) at col 16 (idx 15).
    {_char, fg0, _bg, _blink} = Enum.at(keys_row, 12)
    {_char, fg3, _bg, _blink} = Enum.at(keys_row, 15)
    {_char, fg1, _bg, _blink} = Enum.at(keys_row, 13)

    assert fg0 == 9
    assert fg3 == 12
    # Unowned slot keeps the default white-on-blue blank.
    assert fg1 == 15
  end

  test "T and H keybind rows use the grey key box" do
    rows = Sidebar.rows(world())
    torch_row = Enum.at(rows, 14)
    help_row = Enum.at(rows, 16)

    # The key box is " X " painted at col 3; the letter sits at col 4 (idx 3).
    for row <- [torch_row, help_row] do
      {_char, fg, bg, _blink} = Enum.at(row, 3)
      assert {fg, bg} == {0, 7}
    end
  end

  test "paused? overlays 'Pausing...' at row 6" do
    rows = Sidebar.rows(world(), paused?: true)
    text = cell_string(Enum.at(rows, 5))

    assert text =~ "Pausing..."
    # "P" lands at col 5 (idx 4) with fg white on bg blue per
    # VideoWriteText(64, 5, $1F, ...).
    {char, fg, bg, _blink} = Enum.at(Enum.at(rows, 5), 4)
    assert char == "P"
    assert {fg, bg} == {15, 1}
  end

  test "without :paused? the row 6 stays blank" do
    rows = Sidebar.rows(world())
    refute cell_string(Enum.at(rows, 5)) =~ "Pausing"
  end

  test "B (Be quiet) and P (Pause) use a cyan key box instead of grey" do
    rows = Sidebar.rows(world())
    be_quiet_row = Enum.at(rows, 15)
    pause_row = Enum.at(rows, 22)

    for row <- [be_quiet_row, pause_row] do
      {_char, fg, bg, _blink} = Enum.at(row, 3)
      assert {fg, bg} == {0, 3}
    end
  end

  test "Move and Shoot rows align their arrow blocks and labels" do
    rows = Sidebar.rows(world())
    move_row = Enum.at(rows, 18)
    shoot_row = Enum.at(rows, 19)

    move_text = cell_string(move_row)
    shoot_text = cell_string(shoot_row)

    # Word "Move"/"Shoot" starts at col 14 (idx 13) on both rows.
    assert String.slice(move_text, 13, 4) == "Move"
    assert String.slice(shoot_text, 13, 5) == "Shoot"

    # Shoot's grey bar runs continuously from "Shift" through the arrows.
    assert {_c, _fg, 7, _b} = Enum.at(shoot_row, 2)
    assert {_c, _fg, 7, _b} = Enum.at(shoot_row, 7)
    assert {_c, _fg, 7, _b} = Enum.at(shoot_row, 11)

    # Move row keeps cyan for the arrow block instead.
    assert {_c, _fg, 3, _b} = Enum.at(move_row, 8)
    assert {_c, _fg, 3, _b} = Enum.at(move_row, 11)
  end
end
