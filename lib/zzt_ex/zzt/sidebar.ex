defmodule ZztEx.Zzt.Sidebar do
  @moduledoc """
  Render the stock ZZT in-game sidebar as a 20x25 cell grid.

  The output shape matches `ZztEx.Zzt.Render.rows/2`: a list of rows, each a
  list of `{char, fg, bg, blink}` tuples. The caller composes the sidebar
  alongside the 60x25 board to reproduce ZZT's 80x25 text-mode display.
  """

  alias ZztEx.Zzt.{Cp437, World}

  @type cell :: {String.t(), 0..15, 0..15, boolean()}

  @width 20
  @height 25

  # Palette indices used across the panel.
  @blue 1
  @cyan 3
  @brown 6
  @grey 7
  @yellow 14
  @white 15
  @black 0

  # CP437 icon bytes.
  @icon_smiley 0x02
  @icon_ammo 0x84
  @icon_torch 0x9D
  @icon_gem 0x04
  @icon_key 0x0C
  @arrow_up 0x18
  @arrow_down 0x19
  @arrow_right 0x1A
  @arrow_left 0x1B
  @space 0x20

  @doc "Sidebar width in cells (always 20)."
  def width, do: @width
  @doc "Sidebar height in cells (always 25)."
  def height, do: @height

  @doc """
  Build the sidebar rows from a `%World{}`. Values displayed (health, ammo,
  keys, etc.) come straight from the world struct — there is no game state
  yet, so these are the starting values from the `.zzt` header.
  """
  @spec rows(World.t()) :: [[cell()]]
  def rows(%World{} = world) do
    [
      blank_row(),
      dash_row(),
      title_row(),
      dash_row(),
      blank_row(),
      stat_row(@icon_smiley, @white, "Health:", world.health),
      stat_row(@icon_ammo, @cyan, "Ammo:", world.ammo),
      stat_row(@icon_torch, @brown, "Torches:", world.torches),
      stat_row(@icon_gem, @cyan, "Gems:", world.gems),
      score_row(world.score),
      keys_row(world.keys),
      blank_row(),
      keybind_row(?T, "Torch"),
      keybind_row(?B, "Be quiet"),
      keybind_row(?H, "Help"),
      blank_row(),
      move_row(),
      shoot_row(),
      blank_row(),
      keybind_row(?S, "Save game"),
      keybind_row(?P, "Pause"),
      keybind_row(?Q, "Quit"),
      blank_row(),
      blank_row(),
      blank_row()
    ]
  end

  defp cell(char_byte, fg, bg), do: {Cp437.char(char_byte), fg, bg, false}
  defp blank_cell, do: cell(@space, @white, @blue)
  defp blank_row, do: List.duplicate(blank_cell(), @width)

  # Paint `text` onto `row` starting at 1-indexed `col`, using fg/bg for each
  # cell. Characters that fall past the sidebar edge are silently dropped.
  defp paint(row, col, text, fg, bg) when is_binary(text) do
    cells = for <<b <- text>>, do: cell(b, fg, bg)
    overlay(row, col - 1, cells)
  end

  defp overlay(row, _idx, []), do: row

  defp overlay(row, idx, [cell | rest]) when idx >= 0 and idx < @width do
    overlay(List.replace_at(row, idx, cell), idx + 1, rest)
  end

  defp overlay(row, _idx, _cells), do: row

  defp dash_row do
    paint(blank_row(), 3, "- - - - - - -", @white, @blue)
  end

  defp title_row do
    paint(blank_row(), 8, "  ZZT  ", @black, @grey)
  end

  defp stat_row(icon_byte, icon_fg, label, value) do
    value_text = Integer.to_string(value)
    # Right-align the label so every colon lands at column 13.
    label_col = 14 - String.length(label)

    blank_row()
    |> paint(3, <<icon_byte>>, icon_fg, @blue)
    |> paint(label_col, label, @yellow, @blue)
    |> paint(15, value_text, @white, @blue)
  end

  defp score_row(score) do
    value_text = Integer.to_string(score)

    blank_row()
    |> paint(8, "Score:", @yellow, @blue)
    |> paint(15, value_text, @white, @blue)
  end

  defp keys_row(keys) do
    row =
      blank_row()
      |> paint(3, <<@icon_key>>, @white, @blue)
      |> paint(9, "Keys:", @yellow, @blue)

    # Keys slots 0..6 correspond to blue/green/cyan/red/purple/yellow/white,
    # which are palette indices 9..15. Render one ♀ glyph per owned key.
    keys
    |> Enum.with_index()
    |> Enum.reduce(row, fn
      {true, idx}, acc -> paint(acc, 15 + idx, <<@icon_key>>, 9 + idx, @blue)
      {false, _idx}, acc -> acc
    end)
  end

  defp keybind_row(letter, description) do
    blank_row()
    |> paint(2, " #{<<letter>>} ", @black, @grey)
    |> paint(6, description, @white, @blue)
  end

  defp move_row do
    blank_row()
    |> paint(2, <<@arrow_up, @arrow_down, @arrow_right, @arrow_left>>, @black, @cyan)
    |> paint(7, "Move", @white, @blue)
  end

  defp shoot_row do
    blank_row()
    |> paint(1, " Shift ", @black, @grey)
    |> paint(9, <<@arrow_up, @arrow_down, @arrow_right, @arrow_left>>, @black, @cyan)
    |> paint(14, "Shoot", @white, @blue)
  end
end
