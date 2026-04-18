defmodule ZztEx.Zzt.Rle do
  @moduledoc """
  Run-length decoder for ZZT board tile streams.

  Each run is three bytes: `count`, `element_id`, `color`. A `count` of 0 is
  interpreted as 256. Decoding stops once `tile_count` tiles have been
  produced (ZZT boards always expect exactly 1500 = 60x25).
  """

  @doc """
  Decode `binary` into a list of `{element_id, color}` tuples of length
  `tile_count`. Returns `{tiles, rest}` where `rest` is whatever is left in
  the input after the last run needed to fill the grid.
  """
  @spec decode(binary(), non_neg_integer()) :: {[{0..255, 0..255}], binary()}
  def decode(binary, tile_count) when is_binary(binary) and tile_count >= 0 do
    decode(binary, tile_count, [])
  end

  defp decode(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp decode(<<raw_count, element, color, rest::binary>>, remaining, acc) do
    count = if raw_count == 0, do: 256, else: raw_count
    take = min(count, remaining)
    acc = prepend(acc, {element, color}, take)
    decode(rest, remaining - take, acc)
  end

  defp prepend(acc, _tile, 0), do: acc
  defp prepend(acc, tile, n), do: prepend([tile | acc], tile, n - 1)
end
