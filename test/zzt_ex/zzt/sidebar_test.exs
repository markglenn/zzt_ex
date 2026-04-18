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

  test "every cell has a blue background by default" do
    rows = Sidebar.rows(world())
    # Count background 1 (blue) cells — any overlay cells (grey/cyan)
    # will bring this below 500, but the vast majority should stay blue.
    blue_count =
      rows
      |> List.flatten()
      |> Enum.count(fn {_char, _fg, bg, _blink} -> bg == 1 end)

    total = Sidebar.width() * Sidebar.height()
    assert blue_count > div(total, 2)
  end

  test "health row renders smiley + 'Health:' + value" do
    rows = Sidebar.rows(world(health: 93))
    # Row order: blank, dash, title, dash, blank, then Health.
    health_row = Enum.at(rows, 5)
    text = cell_string(health_row)

    assert text =~ "Health:"
    assert text =~ "93"
    # Smiley glyph at col 3 (CP437 0x02 → ☻ U+263B).
    {char, _fg, _bg, _blink} = Enum.at(health_row, 2)
    assert char == <<0x263B::utf8>>
  end

  test "owned keys render as colored ♀ glyphs" do
    rows = Sidebar.rows(world(keys: [true, false, false, true, false, false, false]))
    keys_row = Enum.at(rows, 10)
    # Keys slots start at column 15. Slot 0 (blue key) is index 14, slot 3
    # (red key) is index 17. Off-slots stay as the default blue-bg space.
    {_char, fg0, _bg, _blink} = Enum.at(keys_row, 14)
    {_char, fg3, _bg, _blink} = Enum.at(keys_row, 17)
    {_char, fg1, _bg, _blink} = Enum.at(keys_row, 15)

    # Palette 9 = light blue, 12 = light red.
    assert fg0 == 9
    assert fg3 == 12
    # Unowned slot keeps the default white-on-blue blank.
    assert fg1 == 15
  end

  test "score row has the label right-aligned to column 13" do
    rows = Sidebar.rows(world(score: 30))
    text = cell_string(Enum.at(rows, 9))

    # "Score:" starts at col 8 (1-based) so the ':' lands at col 13.
    assert String.slice(text, 7, 6) == "Score:"
    # Value at col 15..
    assert String.slice(text, 14, 2) == "30"
  end
end
