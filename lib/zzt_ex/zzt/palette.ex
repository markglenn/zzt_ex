defmodule ZztEx.Zzt.Palette do
  @moduledoc """
  The 16-color DOS/EGA/VGA text-mode palette used by ZZT.

  ZZT tiles store a single color byte where the high nibble is the background
  (0-7, or 0-15 when blinking is disabled) and the low nibble is the
  foreground (0-15). Index 0 is black and 15 is white.
  """

  @colors {
    {0, 0, 0},
    {0, 0, 170},
    {0, 170, 0},
    {0, 170, 170},
    {170, 0, 0},
    {170, 0, 170},
    {170, 85, 0},
    {170, 170, 170},
    {85, 85, 85},
    {85, 85, 255},
    {85, 255, 85},
    {85, 255, 255},
    {255, 85, 85},
    {255, 85, 255},
    {255, 255, 85},
    {255, 255, 255}
  }

  @doc """
  Return `{r, g, b}` for a palette index in `0..15`.
  """
  @spec rgb(0..15) :: {0..255, 0..255, 0..255}
  def rgb(index) when index in 0..15, do: elem(@colors, index)

  @doc """
  Decode a color byte into `{fg_index, bg_index, blink?}`.

  When the high bit is set the foreground is expected to blink; this parser
  surfaces the flag but callers may ignore it and render the cell statically.
  """
  @spec decode(0..255) :: {0..15, 0..7, boolean()}
  def decode(byte) when byte in 0..255 do
    fg = Bitwise.band(byte, 0x0F)
    bg = Bitwise.band(Bitwise.bsr(byte, 4), 0x07)
    blink = Bitwise.band(byte, 0x80) != 0
    {fg, bg, blink}
  end

  @doc """
  Hex CSS color string (e.g. `"#00aaaa"`) for a palette index.
  """
  @spec hex(0..15) :: String.t()
  def hex(index) do
    {r, g, b} = rgb(index)
    "#" <> to_hex(r) <> to_hex(g) <> to_hex(b)
  end

  defp to_hex(byte) do
    byte |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()
  end
end
