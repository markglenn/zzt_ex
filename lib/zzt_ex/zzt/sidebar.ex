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

  Options:

    * `:paused?` — overlay "Pausing..." at row 6, matching the
      `VideoWriteText(64, 5, $1F, 'Pausing...')` in the reference's
      paused branch (GAME.PAS:1533).
    * `:time_remaining` — when > 0, draw a "Time: NNN" row at row 7
      per GAME.PAS:1097-1100.
  """
  @spec rows(map(), keyword()) :: [[cell()]]
  def rows(state, opts \\ []) do
    rows = base_rows(state)

    rows =
      if Keyword.get(opts, :paused?, false),
        do: List.replace_at(rows, 5, pausing_row()),
        else: rows

    case Keyword.get(opts, :time_remaining, 0) do
      n when is_integer(n) and n > 0 -> List.replace_at(rows, 6, time_row(n))
      _ -> rows
    end
  end

  defp base_rows(state) do
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

  # Reference writes " Pausing..." at VGA col 64 row 5 with $1F (white
  # on blue) — sidebar-local 1-indexed col 5. The leading space lives
  # in the source literal so we keep it too.
  defp pausing_row do
    paint(blank_row(), 5, "Pausing...", @white, @blue)
  end

  # `'   Time:'` at col 64 + `numStr + ' '` at col 72 per
  # GAME.PAS:1097-1100. Colon lands at col 12 like the stat rows.
  defp time_row(remaining) do
    label_col = @colon_col - String.length("Time:") + 1

    blank_row()
    |> paint(label_col, "Time:", @yellow, @blue)
    |> paint(@value_col, Integer.to_string(remaining), @yellow, @blue)
  end

  @doc """
  Build the title-screen ("Monitor") sidebar — the E_MONITOR branch
  of GameDrawSidebar (GAME.PAS:1456-1482). Every command the
  reference draws is shown; only Play/World/About/Speed are wired up
  in the LiveView keydown path, the rest are visual-only stubs until
  a future pass implements them.

  Opts:

    * `:world_name` — shown on row 9 next to the W keybind, `"Untitled"`
      when missing.
    * `:speed` — 1..9 slider position; drives the arrow indicator on
      row 23. Defaults to 5 (the reference's `TickSpeed := 4` / slider
      position 5).
  """
  @spec monitor_rows(keyword()) :: [[cell()]]
  def monitor_rows(opts \\ []) do
    world_name = Keyword.get(opts, :world_name, "")
    speed = Keyword.get(opts, :speed, 5)

    [
      dash_row(),
      title_row(),
      dash_row(),
      blank_row(),
      blank_row(),
      pick_command_row(),
      blank_row(),
      world_key_row(),
      world_name_row(world_name),
      blank_row(),
      blank_row(),
      play_key_row(),
      restore_key_row(),
      quit_key_row(),
      blank_row(),
      blank_row(),
      about_key_row(),
      high_scores_key_row(),
      board_editor_key_row(),
      blank_row(),
      blank_row(),
      speed_label_row(),
      speed_arrow_row(speed),
      speed_track_row(),
      blank_row()
    ]
  end

  # `VideoWriteText(62, 5, $1B, 'Pick a command:')`. $1B = fg 11 / bg 1.
  defp pick_command_row do
    paint(blank_row(), 3, "Pick a command:", @light_cyan, @blue)
  end

  # `VideoWriteText(62, 7, $30, ' W ')` + `VideoWriteText(65, 7, $1E, ' World:')`.
  # $30 = black on cyan, $1E = yellow on blue.
  defp world_key_row do
    blank_row()
    |> paint(@icon_col, " W ", @black, @cyan)
    |> paint(@desc_col, "World:", @yellow, @blue)
  end

  # `VideoWriteText(69, 8, $1F, World.Info.Name | 'Untitled')`.
  # VGA col 69 = sidebar-local 1-indexed col 10. $1F = white on blue.
  defp world_name_row(""), do: world_name_row("Untitled")
  defp world_name_row(nil), do: world_name_row("Untitled")
  defp world_name_row(name), do: paint(blank_row(), 10, name, @white, @blue)

  # `VideoWriteText(62, 11, $70, ' P ')` + `VideoWriteText(65, 11, $1F, ' Play')`.
  defp play_key_row do
    blank_row()
    |> paint(@icon_col, " P ", @black, @grey)
    |> paint(@desc_col, "Play", @white, @blue)
  end

  # `VideoWriteText(62, 12, $30, ' R ')` + `VideoWriteText(65, 12, $1E, ' Restore game')`.
  defp restore_key_row do
    blank_row()
    |> paint(@icon_col, " R ", @black, @cyan)
    |> paint(@desc_col, "Restore game", @yellow, @blue)
  end

  # `VideoWriteText(62, 13, $70, ' Q ')` + `VideoWriteText(65, 13, $1E, ' Quit')`.
  defp quit_key_row do
    blank_row()
    |> paint(@icon_col, " Q ", @black, @grey)
    |> paint(@desc_col, "Quit", @yellow, @blue)
  end

  # `VideoWriteText(62, 16, $30, ' A ')` + `VideoWriteText(65, 16, $1F, ' About ZZT!')`.
  defp about_key_row do
    blank_row()
    |> paint(@icon_col, " A ", @black, @cyan)
    |> paint(@desc_col, "About ZZT!", @white, @blue)
  end

  # `VideoWriteText(62, 17, $70, ' H ')` + `VideoWriteText(65, 17, $1E, ' High Scores')`.
  defp high_scores_key_row do
    blank_row()
    |> paint(@icon_col, " H ", @black, @grey)
    |> paint(@desc_col, "High Scores", @yellow, @blue)
  end

  # `VideoWriteText(62, 18, $30, ' E ')` + `VideoWriteText(65, 18, $1E, ' Board Editor')`.
  # The reference draws this only when EditorEnabled; we render it
  # unconditionally for layout completeness and let the key handler
  # stay a no-op.
  defp board_editor_key_row do
    blank_row()
    |> paint(@icon_col, " E ", @black, @cyan)
    |> paint(@desc_col, "Board Editor", @yellow, @blue)
  end

  # Mirrors SidebarPromptSlider(false, 66, 21, 'Game speed:;FS', ...)
  # with editable=false. Three rows at y=21..23 — label, arrow, track.
  # VGA col 66 = sidebar-local col 7. Colors match $1E (prompt), $1E
  # (track); the arrow is always $9F in the editable case but this is
  # the read-only view so we lean on the same yellow as the label.
  defp speed_label_row do
    blank_row()
    |> paint(@icon_col, " S ", @black, @grey)
    |> paint(7, "Game speed:", @yellow, @blue)
  end

  defp speed_arrow_row(speed) do
    # `VideoWriteText(x + value + 1, y + 1, $9F, #31)` — value is 0..8
    # for slider positions 1..9, so our 1-indexed column lands at
    # `7 + value + 1` = 8..16.
    value = max(min(speed - 1, 8), 0)
    paint(blank_row(), 7 + value + 1, <<0x1F>>, @white, @blue)
  end

  defp speed_track_row do
    paint(blank_row(), 7, "F....:....S", @yellow, @blue)
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
