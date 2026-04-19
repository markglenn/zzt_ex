defmodule ZztEx.Zzt.Render do
  @moduledoc """
  Translate parsed board tiles into renderable cells.

  A rendered cell is `{char, fg, bg, blink}` where:

    * `char`  — one-character UTF-8 binary, CP437-decoded
    * `fg`    — foreground palette index 0..15
    * `bg`    — background palette index 0..7
    * `blink` — whether the foreground should blink (high bit of color)

  This module models ZZT's draw layer: animated elements cycle chars based
  on the caller-supplied `:tick`, directional elements read the stat's step
  vector, Line picks its box-drawing glyph from its 4 cardinal neighbors,
  and the high bit of the color byte surfaces as a blink flag.
  """

  alias ZztEx.Zzt.{Board, Cp437, Element, Stat}

  @type cell :: {char :: String.t(), fg :: 0..15, bg :: 0..15, blink :: boolean()}

  @empty 0
  @board_edge 1
  @player 4
  @torch_item 6
  @scroll 10
  @passage 11
  @bomb 13
  @star 15
  @conveyor_cw 16
  @conveyor_ccw 17
  @invisible 28
  @transporter 30
  @line 31
  @object 36
  @spinning_gun 39
  @pusher 40

  # Ellipse the torch illuminates — a rectangle `(2*TORCH_DX+1) x (2*TORCH_DY+1)`
  # clipped to `(ix - x)^2 + (iy - y)^2 * 2 < TORCH_DIST_SQR`, matching
  # `BoardDrawTile` / `DrawPlayerSurroundings`.
  @torch_dist_sqr 50
  # Dark tile glyph: CP437 0xB0 (light shade) with fg grey, bg black.
  @dark_char 0xB0

  # ZZT animation frame tables, lifted from Elements.pas in the 2020 source
  # release. All indices are 0-based.
  @star_chars {0x2F, 0x7C, 0x5C, 0x2D}
  @conveyor_cw_chars {0xB3, 0x2F, 0xC4, 0x5C}
  @conveyor_ccw_chars {0xB3, 0x5C, 0xC4, 0x2F}
  # Transporter: frames 0..3 are "inbound" (west/north), 4..7 are "outbound"
  # (east/south). Selected by the stat's step vector.
  @transporter_ns {0x5E, 0x7E, 0x5E, 0x2D, 0x76, 0x5F, 0x76, 0x2D}
  @transporter_ew {0x28, 0x3C, 0x28, 0x2D, 0x29, 0x3E, 0x29, 0x2D}
  @gun_chars {0x18, 0x1A, 0x19, 0x1B}
  # Line: indexed by (1 + north + south*2 + west*4 + east*8), -1 to make 0-based.
  @line_chars {0xF9, 0xD0, 0xD2, 0xBA, 0xB5, 0xBC, 0xBB, 0xB9, 0xC6, 0xC8, 0xC9, 0xCC, 0xCD, 0xCA,
               0xCB, 0xCE}

  @doc """
  Render `board` as a list of 25 rows, each a list of 60 `cell` tuples.

  Options:

    * `:tick`           — integer advanced by the caller each animation
      frame. Drives Star, Conveyor, Transporter, SpinningGun cycling.
    * `:title_screen?`  — blank the player avatar (ZZT swaps it for a
      Monitor on board 0).
    * `:message`        — `{text, ticks}` overlay centered on the bottom
      row (`y = 25`), mirroring `ElementMessageTimerTick`. `ticks`
      cycles the foreground color through palette 9..15.
    * `:dark?`          — board is dark. Tiles outside the torch ellipse
      render as CP437 0xB0 ("░"), except for `VisibleInDark` elements
      (player, torch pickup, passage) which always show.
    * `:torch_ticks`    — remaining torch time; when > 0 the ellipse
      around the player stat is rendered normally.
    * `:paused?`        — when true, mark the player cell as blinking
      so the glyph flashes on/off at ~1.875 Hz, matching the
      `pauseBlink` toggle at GAME.PAS:1519-1531.
  """
  @spec rows(Board.t(), keyword()) :: [[cell()]]
  def rows(%Board{} = board, opts \\ []) do
    tick = Keyword.get(opts, :tick, 0)
    title_screen? = Keyword.get(opts, :title_screen?, false)
    stats_by_xy = stats_by_position(board.stats)
    player_xy = player_position(board.stats)
    dark? = Keyword.get(opts, :dark?, false)
    torch_ticks = Keyword.get(opts, :torch_ticks, 0)
    paused? = Keyword.get(opts, :paused?, false)
    grid = List.to_tuple(board.tiles)

    rows =
      for y <- 1..Board.height() do
        for x <- 1..Board.width() do
          if title_screen? and player_xy == {x, y} do
            {" ", 7, 0, false}
          else
            {element, color} = tile_at(grid, x, y)

            cell =
              if dark? and darken?(element, x, y, player_xy, torch_ticks) do
                {Cp437.char(@dark_char), 7, 0, false}
              else
                compute_cell(grid, x, y, element, color, Map.get(stats_by_xy, {x, y}), tick)
              end

            if paused? and player_xy == {x, y} do
              blink_cell(cell)
            else
              cell
            end
          end
        end
      end

    overlay_message(rows, Keyword.get(opts, :message))
  end

  defp blink_cell({char, fg, bg, _blink}), do: {char, fg, bg, true}

  # VisibleInDark elements (player/torch pickup/passage) are never darkened;
  # otherwise we darken unless the torch is lit and the cell sits inside
  # the ellipse `(ix - px)^2 + (iy - py)^2 * 2 < TORCH_DIST_SQR`.
  defp darken?(element, _x, _y, _player_xy, _torch_ticks)
       when element in [@player, @torch_item, @passage],
       do: false

  defp darken?(_element, _x, _y, nil, _torch_ticks), do: true
  defp darken?(_element, _x, _y, _player_xy, torch_ticks) when torch_ticks <= 0, do: true

  defp darken?(_element, x, y, {px, py}, _torch_ticks) do
    dx = x - px
    dy = y - py
    dx * dx + dy * dy * 2 >= @torch_dist_sqr
  end

  defp overlay_message(rows, nil), do: rows
  defp overlay_message(rows, {_text, ticks}) when ticks <= 0, do: rows

  defp overlay_message(rows, {text, ticks}) do
    # Truncate so `' ' + text + ' '` fits inside 60 columns.
    max_inner = 58
    text = if String.length(text) > max_inner, do: String.slice(text, 0, max_inner), else: text
    padded = " " <> text <> " "
    len = String.length(padded)

    # `(60 - length) div 2` in 0-indexed video-space → our 1-indexed col.
    start_col = div(60 - len, 2) + 1
    fg = 9 + rem(ticks, 7)

    cells = for <<b <- padded>>, do: {Cp437.char(b), fg, 0, false}

    row_idx = Board.height() - 1
    old_row = Enum.at(rows, row_idx)
    new_row = splice(old_row, start_col - 1, cells)
    List.replace_at(rows, row_idx, new_row)
  end

  defp splice(row, _idx, []), do: row

  defp splice(row, idx, [cell | rest]) when idx >= 0 and idx < 60 do
    splice(List.replace_at(row, idx, cell), idx + 1, rest)
  end

  defp splice(row, _idx, _cells), do: row

  defp compute_cell(grid, x, y, element, color, stat, tick) do
    cond do
      # Empty and Invisible are always drawn blank; see the Foundation
      # commit for why stored color/char bytes leak through otherwise.
      element == @empty or element == @invisible ->
        {" ", 7, 0, false}

      Element.text?(element) ->
        bg = Element.text_background(element) || 0
        {Cp437.char(color), 15, bg, false}

      true ->
        <<bg_nibble::4, fg::4>> = <<color>>
        bg = Bitwise.band(bg_nibble, 0x07)
        blink = Bitwise.band(color, 0x80) != 0
        {char_byte, fg} = draw(element, stat, tick, grid, x, y, fg)
        {Cp437.char(char_byte), fg, bg, blink}
    end
  end

  # Returns {char_byte, fg}. Most elements keep the stored fg; Star and
  # Scroll override because ZZT cycles their color through palette 9..15
  # on every tick (ElementStarDraw / ElementScrollTick).
  defp draw(@star, _stat, tick, _grid, _x, _y, _fg),
    do: {elem(@star_chars, rem(tick, 4)), 9 + rem(tick, 7)}

  defp draw(@scroll, _stat, tick, _grid, _x, _y, _fg),
    do: {Element.default_char(@scroll), 9 + rem(tick, 7)}

  defp draw(@conveyor_cw, _stat, tick, _grid, _x, _y, fg),
    do: {elem(@conveyor_cw_chars, rem(tick, 4)), fg}

  defp draw(@conveyor_ccw, _stat, tick, _grid, _x, _y, fg),
    do: {elem(@conveyor_ccw_chars, rem(tick, 4)), fg}

  defp draw(@spinning_gun, _stat, tick, _grid, _x, _y, fg),
    do: {elem(@gun_chars, rem(tick, 4)), fg}

  defp draw(@transporter, %Stat{} = stat, tick, _grid, _x, _y, fg),
    do: {transporter_char(stat.step_x, stat.step_y, tick), fg}

  defp draw(@pusher, %Stat{} = stat, _tick, _grid, _x, _y, fg),
    do: {pusher_char(stat.step_x, stat.step_y), fg}

  defp draw(@object, %Stat{p1: p1}, _tick, _grid, _x, _y, fg),
    do: {p1, fg}

  # Armed bomb counts down; ElementBombDraw swaps the default glyph for
  # the ASCII digit `48 + P1` once P1 > 1, so the player sees "9" through
  # "2" tick past before the blast.
  defp draw(@bomb, %Stat{p1: p1}, _tick, _grid, _x, _y, fg) when p1 > 1,
    do: {0x30 + p1, fg}

  defp draw(@line, _stat, _tick, grid, x, y, fg),
    do: {line_char(grid, x, y), fg}

  defp draw(element, _stat, _tick, _grid, _x, _y, fg),
    do: {Element.default_char(element), fg}

  defp pusher_char(1, _), do: 0x10
  defp pusher_char(-1, _), do: 0x11
  defp pusher_char(_, -1), do: 0x1E
  defp pusher_char(_, _), do: 0x1F

  defp transporter_char(0, step_y, tick) do
    offset = if step_y == 1, do: 4, else: 0
    elem(@transporter_ns, offset + rem(tick, 4))
  end

  defp transporter_char(step_x, _step_y, tick) do
    offset = if step_x == 1, do: 4, else: 0
    elem(@transporter_ew, offset + rem(tick, 4))
  end

  defp line_char(grid, x, y) do
    n = line_neighbor?(grid, x, y - 1)
    s = line_neighbor?(grid, x, y + 1)
    w = line_neighbor?(grid, x - 1, y)
    e = line_neighbor?(grid, x + 1, y)

    v =
      if(n, do: 1, else: 0) +
        if(s, do: 2, else: 0) +
        if(w, do: 4, else: 0) +
        if e, do: 8, else: 0

    elem(@line_chars, v)
  end

  # Off-board is treated as a connecting neighbor so lines at the edge
  # reach out to the playfield border, matching ZZT's behavior.
  defp line_neighbor?(_grid, x, _y) when x < 1, do: true
  defp line_neighbor?(_grid, _x, y) when y < 1, do: true

  defp line_neighbor?(_grid, x, _y) when x > 60, do: true
  defp line_neighbor?(_grid, _x, y) when y > 25, do: true

  defp line_neighbor?(grid, x, y) do
    {e, _} = tile_at(grid, x, y)
    e == @line or e == @board_edge
  end

  defp tile_at(grid, x, y), do: elem(grid, (y - 1) * Board.width() + (x - 1))

  # Stats after index 0 map by their {x,y}. Player is excluded so the
  # title-screen blanking and the main tile lookup don't compete.
  defp stats_by_position(stats) do
    stats
    |> Enum.drop(1)
    |> Enum.reduce(%{}, fn
      %Stat{x: x, y: y} = stat, acc -> Map.put(acc, {x, y}, stat)
    end)
  end

  defp player_position([%Stat{x: x, y: y} | _]), do: {x, y}
  defp player_position(_), do: nil
end
