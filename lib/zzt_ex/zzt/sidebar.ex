defmodule ZztEx.Zzt.Sidebar do
  @moduledoc """
  Render the stock ZZT in-game sidebar as a 20x25 cell grid.

  The output shape matches `ZztEx.Zzt.Render.rows/2`: a list of rows, each a
  list of `{char, fg, bg, blink}` tuples. The caller composes the sidebar
  alongside the 60x25 board to reproduce ZZT's 80x25 text-mode display.

  Layout conventions (1-indexed columns):

    * cols 1-3 are always blank blue — the visual gap between the board
      and the sidebar content
    * stat rows: icon at col 4, label right-aligned so the colon lands at
      col 15, value starts at col 16 (no gap between colon and value)
    * keybind rows: letter at col 4 (on grey or cyan for toggle keys),
      description at col 7
    * move / shoot rows: arrow block at cols 9-12, word at col 14, so the
      two rows align under each other
  """

  alias ZztEx.Zzt.Cp437

  @type cell :: {String.t(), 0..15, 0..15, boolean()}

  @width 20
  @height 25

  # Palette indices used across the panel.
  @blue 1
  @cyan 3
  @brown 6
  @grey 7
  @light_cyan 11
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

  @icon_col 3
  @colon_col 12
  @value_col 13
  @desc_col 7
  @arrow_col 8
  @word_col 14
  # Reference draws the torch gauge at VGA cols 75..78 on the torch
  # row (GAME.PAS:1124). With the sidebar anchored at VGA col 60 those
  # are sidebar-local 1-indexed cols 16..19.
  @torch_bar_col 16
  @torch_bar_len 4

  @torch_duration 200

  @doc "Sidebar width in cells (always 20)."
  def width, do: @width
  @doc "Sidebar height in cells (always 25)."
  def height, do: @height

  @doc """
  Build the sidebar rows from any struct/map that has the expected
  player-stat fields (`:health`, `:ammo`, `:gems`, `:keys`, `:torches`,
  `:score`). A `%World{}` matches out of the box; the runtime
  `ZztEx.Zzt.Game.player_state()` also matches, so the same renderer
  works for the world header and for live play.
  """
  @spec rows(map()) :: [[cell()]]
  def rows(state) do
    # Layout mirrors GameDrawSidebar (GAME.PAS:1420), reference row
    # numbering 0..24 → our 1..25. Stats start at row 8 (ref row 7).
    [
      dash_row(),
      title_row(),
      dash_row(),
      blank_row(),
      blank_row(),
      blank_row(),
      blank_row(),
      stat_row(@icon_smiley, @white, "Health:", state.health),
      stat_row(@icon_ammo, @light_cyan, "Ammo:", state.ammo),
      torches_row(state),
      stat_row(@icon_gem, @light_cyan, "Gems:", state.gems),
      score_row(state.score),
      keys_row(state.keys),
      blank_row(),
      keybind_row(?T, "Torch"),
      keybind_row(?B, "Be quiet", @cyan),
      keybind_row(?H, "Help"),
      blank_row(),
      move_row(),
      shoot_row(),
      blank_row(),
      keybind_row(?S, "Save game"),
      keybind_row(?P, "Pause", @cyan),
      keybind_row(?Q, "Quit"),
      blank_row()
    ]
  end

  defp cell(char_byte, fg, bg), do: {Cp437.char(char_byte), fg, bg, false}

  defp blank_row do
    @space
    |> cell(@white, @blue)
    |> List.duplicate(@width)
  end

  # Paint `text` onto `row` starting at 1-indexed `col`. Cells past the
  # sidebar edge are silently dropped (keeps overlong values from crashing).
  defp paint(row, col, text, fg, bg) when is_binary(text) do
    cells = for <<b <- text>>, do: cell(b, fg, bg)
    overlay(row, col - 1, cells)
  end

  defp overlay(row, _idx, []), do: row

  defp overlay(row, idx, [cell | rest]) when idx >= 0 and idx < @width do
    overlay(List.replace_at(row, idx, cell), idx + 1, rest)
  end

  defp overlay(row, _idx, _cells), do: row

  # The 11-char dash row and 11-char grey title box share the same span so
  # they line up visually. Both sit at col 5..15.
  defp dash_row do
    paint(blank_row(), 6, "- - - - -", @white, @blue)
  end

  defp title_row do
    paint(blank_row(), 3, "      ZZT      ", @black, @grey)
  end

  # Mirrors the reference's torch gauge at SidebarUpdate: four cells
  # at the sidebar's right edge, each either #177 (▒ filled) or #176
  # (░ empty), one segment lighting up per 40 ticks of torch time.
  # Hidden entirely when no torch is burning.
  defp torches_row(state) do
    row = stat_row(@icon_torch, @brown, "Torches:", state.torches)

    case Map.get(state, :torch_ticks, 0) do
      n when n <= 0 -> row
      ticks -> overlay(row, @torch_bar_col - 1, torch_bar_cells(ticks))
    end
  end

  defp torch_bar_cells(ticks) do
    # Reference iterates i = 2..5 and fills when `i <= ticks*5 / 200`.
    # Our loop uses 1..4 so the check is shifted by one.
    filled = div(ticks * 5, @torch_duration)

    for i <- 1..@torch_bar_len do
      char = if i + 1 <= filled, do: 0xB1, else: 0xB0
      cell(char, @brown, @blue)
    end
  end

  defp stat_row(icon_byte, icon_fg, label, value) do
    label_col = @colon_col - String.length(label) + 1

    blank_row()
    |> paint(@icon_col, <<icon_byte>>, icon_fg, @blue)
    |> paint(label_col, label, @yellow, @blue)
    |> paint(@value_col, Integer.to_string(value), @yellow, @blue)
  end

  defp score_row(score) do
    label_col = @colon_col - String.length("Score:") + 1

    blank_row()
    |> paint(label_col, "Score:", @yellow, @blue)
    |> paint(@value_col, Integer.to_string(score), @yellow, @blue)
  end

  defp keys_row(keys) do
    label_col = @colon_col - String.length("Keys:") + 1

    row =
      blank_row()
      |> paint(@icon_col, <<@icon_key>>, @white, @blue)
      |> paint(label_col, "Keys:", @yellow, @blue)

    # Slots 0..6 map to blue/green/cyan/red/purple/yellow/white. The first
    # five fit inside the 20-col sidebar; any beyond that are dropped by
    # `overlay/3` — matching ZZT, which also truncates visually.
    keys
    |> Enum.with_index()
    |> Enum.reduce(row, fn
      {true, idx}, acc ->
        paint(acc, @value_col + idx, <<@icon_key>>, 9 + idx, @blue)

      {false, _idx}, acc ->
        acc
    end)
  end

  # The box color alternates between grey (action keys T/H/S/Q) and cyan
  # (toggle keys B/P) — matching stock ZZT, where B toggles sound and P
  # toggles pause.
  defp keybind_row(letter, description, box_bg \\ @grey) do
    blank_row()
    |> paint(@icon_col, <<" ", letter, " ">>, @black, box_bg)
    |> paint(@desc_col, description, @white, @blue)
  end

  defp move_row do
    blank_row()
    |> paint(@arrow_col, arrows(), @black, @cyan)
    |> paint(@word_col, "Move", @white, @blue)
  end

  # "Shift" (grey) + one grey gap char + arrows (grey) form a single
  # continuous grey bar cols 3..12, matching the original's "white" look.
  defp shoot_row do
    blank_row()
    |> paint(2, " Shift ", @black, @grey)
    |> paint(@arrow_col, arrows(), @black, @grey)
    |> paint(@word_col, "Shoot", @white, @blue)
  end

  defp arrows, do: <<" ", @arrow_up, @arrow_down, @arrow_right, @arrow_left>>
end
