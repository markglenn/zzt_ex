defmodule ZztEx.Zzt.ScrollRender do
  @moduledoc """
  Render a parsed scroll into CP437 cells, matching ZZT's `TextWindow`
  layout from `reconstruction-of-zzt/SRC/TXTWIND.PAS`.

  ZZT opens a 50-column, 18-row window centered on the screen. The
  reference writes the border strings as exactly 49 chars of content,
  leaving the last column blank — we preserve that dimensioning so the
  proportions match pixel-for-pixel.

  Layout (top to bottom):

      row  0 : ╞╤═══...═══╤╡         (top border,  $0F / white on black)
      row  1 : │     Title     │     ($1E / yellow on blue)
      row  2 :  ╞═══...═══╡          (double separator, $0F)
      row  3 :  │                │   (content rows, padded to 45)
      ...
      row 16 :  │                │
      row 17 : ╞╧═══...═══╧╡         (bottom border, $0F)
  """

  alias ZztEx.Zzt.Cp437

  @width 50
  @inner_width 45
  @height 18
  # Reference: lineY := (Y + lpos) - LinePos + (Height div 2) + 1.
  # Translating to our 0-indexed window rows: the selected line always
  # sits at `height div 2 + 1` from the top (row 10 for height 18), and
  # every other line stacks relative to it.
  @middle_row div(@height, 2) + 1
  @first_content_row 3
  @last_content_row @height - 2

  # Palette indices from the reference's VideoWriteText color bytes:
  # $0F = bg 0, fg 15 (white on black).
  # $1E = bg 1, fg 14 (yellow on blue).
  # $1C = bg 1, fg 12 (red on blue).
  # $1F = bg 1, fg 15 (white on blue).
  @border_fg 15
  @border_bg 0
  @text_fg 14
  @text_bg 1
  @accent_fg 15
  @arrow_fg 12

  # CP437 codepoints used in the scroll border.
  @left_junc 0xC6
  @right_junc 0xB5
  @t_down 0xD1
  @t_up 0xCF
  @horiz 0xCD
  @vert 0xB3
  @arrow_right 0xAF
  @arrow_left 0xAE

  @doc """
  Build the 50x18 cell grid for the scroll. The optional `:line_pos`
  points at the currently focused content line (1-indexed into
  `scroll.lines`); that row is rendered with the `»` / `«` selection
  arrows. Out-of-range values hide the arrows entirely.
  """
  @spec render(%{title: String.t(), lines: [String.t()]}, keyword()) ::
          [[ZztEx.Zzt.Render.cell()]]
  def render(scroll, opts \\ []) do
    line_pos = Keyword.get(opts, :line_pos, 1)

    [
      top_border(),
      title_row(scroll.title),
      top_separator()
    ] ++ build_content(scroll.lines, line_pos) ++ [bottom_border()]
  end

  @doc "Scroll width in cells."
  def width, do: @width
  @doc "Scroll height in cells."
  def height, do: @height

  # --- rows ----------------------------------------------------------------

  defp top_border do
    border_row(@t_down, @t_down)
  end

  defp bottom_border do
    border_row(@t_up, @t_up)
  end

  defp border_row(left_corner, right_corner) do
    inner = List.duplicate(cell(@horiz, @border_fg, @border_bg), @inner_width)

    [
      cell(@left_junc, @border_fg, @border_bg),
      cell(left_corner, @border_fg, @border_bg)
    ] ++
      inner ++
      [
        cell(right_corner, @border_fg, @border_bg),
        cell(@right_junc, @border_fg, @border_bg),
        blank_end()
      ]
  end

  # ' ╞═══╡ '  — 45 ═ between single-line-junction brackets.
  defp top_separator do
    inner = List.duplicate(cell(@horiz, @border_fg, @border_bg), @inner_width)

    [blank_end(), cell(@left_junc, @border_fg, @border_bg)] ++
      inner ++
      [cell(@right_junc, @border_fg, @border_bg), blank_end(), blank_end()]
  end

  defp title_row(title) do
    text = pad_centered(truncate(title, @inner_width), @inner_width)

    [blank_end(), cell(@vert, @border_fg, @border_bg)] ++
      text_cells(text, @text_fg, @text_bg) ++
      [cell(@vert, @border_fg, @border_bg), blank_end(), blank_end()]
  end

  defp blank_content_row do
    [blank_end(), cell(@vert, @border_fg, @border_bg)] ++
      List.duplicate(cell(0x20, @text_fg, @text_bg), @inner_width) ++
      [cell(@vert, @border_fg, @border_bg), blank_end(), blank_end()]
  end

  defp content_row(line, selected?) do
    # Inner area (45 wide) holds the line; arrows overlay the first and
    # last inner cells when selected. Text starts two cells in from the
    # inner edge — matching ZZT's 2-col indent.
    {indent_text, fg} = format_line(line)
    text_cells = pad_right(indent_text, @inner_width)

    inner_cells = render_inner(text_cells, selected?, fg)

    [blank_end(), cell(@vert, @border_fg, @border_bg)] ++
      inner_cells ++
      [cell(@vert, @border_fg, @border_bg), blank_end(), blank_end()]
  end

  defp render_inner(text_cells, selected?, fg) do
    cells =
      text_cells
      |> String.to_charlist()
      |> Enum.map(fn byte -> cell(byte, fg, @text_bg) end)

    if selected? do
      cells
      |> List.replace_at(0, cell(@arrow_right, @arrow_fg, @text_bg))
      |> List.replace_at(@inner_width - 1, cell(@arrow_left, @arrow_fg, @text_bg))
    else
      cells
    end
  end

  # For each content row, figure out which line (if any) lands there.
  # Reference `TextWindowDrawLine` has three cases for the virtual line
  # position:
  #
  #   * 1..LineCount  — draw the line (arrows if selected)
  #   * 0 or LineCount+1 — draw the dotted header/footer (StrInnerSep)
  #   * otherwise     — leave the row blank
  defp build_content(lines, line_pos) do
    count = length(lines)

    for window_row <- @first_content_row..@last_content_row do
      lpos = window_row + line_pos - @middle_row

      cond do
        lpos >= 1 and lpos <= count ->
          content_row(Enum.at(lines, lpos - 1), window_row == @middle_row)

        lpos == 0 or lpos == count + 1 ->
          dotted_row()

        true ->
          blank_content_row()
      end
    end
  end

  # `TextWindowStrInnerSep`: bullet (0x07) every 5 cells across the
  # inner 45-wide area, with the 2-cell indent preserved.
  defp dotted_row do
    dots =
      for i <- 1..@inner_width do
        if rem(i, 5) == 0 do
          cell(0x07, @text_fg, @text_bg)
        else
          cell(0x20, @text_fg, @text_bg)
        end
      end

    [blank_end(), cell(@vert, @border_fg, @border_bg)] ++
      dots ++
      [cell(@vert, @border_fg, @border_bg), blank_end(), blank_end()]
  end

  # --- line formatting -----------------------------------------------------

  # `$` lines center in the white accent color.
  defp format_line("$" <> rest) do
    text = String.trim(rest)
    {pad_centered(truncate(text, @inner_width - 4), @inner_width - 4), @accent_fg}
  end

  defp format_line(line) do
    # Plain line: 2-cell indent then the text.
    {"  " <> truncate(line, @inner_width - 2), @text_fg}
  end

  # --- helpers -------------------------------------------------------------

  defp cell(byte, fg, bg), do: {Cp437.char(byte), fg, bg, false}
  # The last cell of each 50-wide row is deliberately left black — ZZT's
  # strings are 49 chars wide and the renderer pads to 50 to keep the
  # grid aligned with the board underneath.
  defp blank_end, do: cell(0x20, @border_fg, @border_bg)

  defp text_cells(text, fg, bg) do
    text
    |> String.to_charlist()
    |> Enum.map(fn byte -> cell(byte, fg, bg) end)
  end

  defp pad_right(text, width) do
    text = truncate(text, width)
    pad = width - String.length(text)
    text <> String.duplicate(" ", max(pad, 0))
  end

  defp pad_centered(text, width) do
    pad = max(width - String.length(text), 0)
    left = div(pad, 2)
    right = pad - left
    String.duplicate(" ", left) <> text <> String.duplicate(" ", right)
  end

  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max)
end
