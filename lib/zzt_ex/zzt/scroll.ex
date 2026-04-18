defmodule ZztEx.Zzt.Scroll do
  @moduledoc """
  Parse the ZZT-OOP code body of a Scroll (element 10) into the plain
  text lines the player will see when they pick it up.

  A real scroll's code can contain ZZT-OOP commands (`#send`, `#zap`,
  labels, conditional jumps, menu options, etc.). Until the full OOP
  interpreter lands we just skip control lines and display the rest —
  most scrolls in stock worlds are purely expository text with only a
  `@Name` header and maybe a `#end`, all of which filter cleanly.

  Lines are CR-separated (0x0D) in the on-disk code and may contain
  CP437 bytes; those get converted to Unicode for browser rendering.
  """

  alias ZztEx.Zzt.Cp437

  @doc """
  Turn the raw scroll-code binary into `%{title: String.t(), lines: [String.t()]}`.

  The title is the `@Name` header if present, otherwise `"Scroll"`.
  """
  @spec parse(binary()) :: %{title: String.t(), lines: [String.t()]}
  def parse(code) when is_binary(code) do
    {title, body} =
      code
      |> split_lines()
      |> extract_title()

    %{title: title, lines: Enum.reject(body, &control_line?/1)}
  end

  # Lines on disk are CR-separated. Also strip a trailing NUL so the last
  # entry doesn't end with a stray glyph.
  defp split_lines(code) do
    code
    |> String.trim_trailing(<<0>>)
    |> String.split("\r")
    |> Enum.map(&cp437_decode/1)
  end

  defp cp437_decode(line) do
    line
    |> :binary.bin_to_list()
    |> Enum.map_join("", fn byte ->
      cond do
        byte in 0x20..0x7E -> <<byte>>
        true -> Cp437.char(byte)
      end
    end)
  end

  # A `@Name` header gives the scroll its title.
  defp extract_title(["@" <> rest | tail]), do: {String.trim(rest), tail}
  defp extract_title(lines), do: {"Scroll", lines}

  # Control lines are anything starting with one of ZZT-OOP's sigils. We
  # don't execute them yet, but we also don't want to leak "#end" / label
  # syntax into the player's reading material.
  defp control_line?(line) do
    String.starts_with?(line, ["#", "@", ":", "/", "?"])
  end
end
