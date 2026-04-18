defmodule ZztEx.Zzt.Render do
  @moduledoc """
  Translate parsed board tiles into renderable cells.

  A rendered cell is a `{char, fg, bg}` tuple, where `char` is a one-character
  UTF-8 binary (CP437-decoded), `fg` is a foreground palette index 0..15, and
  `bg` is a background palette index 0..7.

  Object elements (ID 36) use their stat's `p1` as the display character; the
  board stat list is walked once to build a position → stat index so the
  renderer can resolve object glyphs in a single pass.
  """

  alias ZztEx.Zzt.{Board, Cp437, Element, Stat}

  @type cell :: {char :: String.t(), fg :: 0..15, bg :: 0..15}

  @doc """
  Render `board` as a list of 25 rows, each a list of 60 `cell` tuples.

  Pass `title_screen?: true` when rendering board 0 of a world — ZZT hides
  the player avatar on the title screen (the runtime swaps the Player tile
  for a Monitor), so the smiley face shouldn't appear there.
  """
  @spec rows(Board.t(), keyword()) :: [[cell()]]
  def rows(%Board{} = board, opts \\ []) do
    title_screen? = Keyword.get(opts, :title_screen?, false)
    stat_chars = stat_char_overrides(board.stats)
    player_pos = title_screen? && player_position(board.stats)

    board.tiles
    |> Enum.chunk_every(Board.width())
    |> Enum.with_index(1)
    |> Enum.map(fn {row_tiles, y} ->
      row_tiles
      |> Enum.with_index(1)
      |> Enum.map(fn {{element, color}, x} ->
        if player_pos == {x, y} do
          {" ", 7, 0}
        else
          cell(element, color, Map.get(stat_chars, {x, y}))
        end
      end)
    end)
  end

  defp player_position([%Stat{x: x, y: y} | _]), do: {x, y}
  defp player_position(_), do: nil

  @object 36
  @invisible 28
  @empty 0

  defp cell(element, color, stat_char) do
    cond do
      # Empty tiles carry residual color bytes left over from whatever
      # element the editor previously placed there. ZZT always draws them
      # as pure black; mirroring the stored bg surfaces editor ghosts as
      # visible grey/green/cyan blocks (e.g. town.zzt's Tigers building).
      element == @empty ->
        {" ", 7, 0}

      # Invisible walls are stored with the color they'll reveal as, but
      # ZZT draws them as fully blank until the player bumps one.
      element == @invisible ->
        {" ", 7, 0}

      Element.text?(element) ->
        bg = Element.text_background(element) || 0
        {Cp437.char(color), 15, bg}

      true ->
        <<bg::4, fg::4>> = <<color>>
        bg = Bitwise.band(bg, 0x07)

        char_byte =
          if element == @object and stat_char, do: stat_char, else: Element.default_char(element)

        {Cp437.char(char_byte), fg, bg}
    end
  end

  # Index every non-player stat by its tile coordinate so object glyphs can
  # be resolved without another pass. Only element 36 (Object) actually uses
  # the override; `cell/3` ignores it for every other element.
  defp stat_char_overrides(stats) do
    stats
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn
      {%Stat{x: x, y: y, p1: p1}, idx}, acc when idx > 0 ->
        Map.put(acc, {x, y}, p1)

      _, acc ->
        acc
    end)
  end
end
