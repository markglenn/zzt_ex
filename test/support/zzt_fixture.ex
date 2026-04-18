defmodule ZztEx.Test.ZztFixture do
  @moduledoc """
  Builds a minimal stock-ZZT world binary for parser tests.

  The fixture creates a world named `"TEST"` with a single board. The board's
  tile grid can be customised via `:tiles` (a list of 1500 `{element, color}`
  tuples); omitting it yields 1500 empty tiles. The first stat is always the
  player.
  """

  @tile_count 1500
  @player_char 0x02

  @doc """
  Build a complete world binary. Options:

    * `:name`         — world name (default `"TEST"`)
    * `:board_title`  — title of the single board (default `"Board 1"`)
    * `:tiles`        — list of `{element, color}` tuples, length 1500
    * `:player_xy`    — `{x, y}` for player stat (default `{30, 13}`)
  """
  def world(opts \\ []) do
    header(opts) <> board(opts)
  end

  defp header(opts) do
    name = Keyword.get(opts, :name, "TEST")
    health = Keyword.get(opts, :health, 100)
    keys = <<0, 0, 0, 0, 0, 0, 0>>

    # 512-byte header = 29 fixed + 21 pascal-name + 210 flags + 252 padding
    <<
      -1::little-signed-16,
      # board_count - 1
      0::little-signed-16,
      # ammo
      0::little-signed-16,
      # gems
      0::little-signed-16,
      keys::binary,
      health::little-signed-16,
      # current_board
      0::little-signed-16,
      # torches
      0::little-signed-16,
      # torch_cycles
      0::little-signed-16,
      # energizer_cycles
      0::little-signed-16,
      # unused
      0::little-signed-16,
      # score
      0::little-signed-16
    >> <>
      pascal(name, 20) <>
      flags() <>
      :binary.copy(<<0>>, 252)
  end

  defp flags do
    # 10 empty flag slots: len byte + 20 data bytes each
    for _ <- 1..10, into: <<>>, do: <<0>> <> :binary.copy(<<0>>, 20)
  end

  defp board(opts) do
    title = Keyword.get(opts, :board_title, "Board 1")
    tiles = Keyword.get(opts, :tiles, List.duplicate({0, 0}, @tile_count))
    {px, py} = Keyword.get(opts, :player_xy, {30, 13})

    tile_bytes = rle_encode(tiles)
    props = properties()
    player_stat = stat(px, py, @player_char, 0x1F)

    body = pascal(title, 50) <> tile_bytes <> props <> player_stat
    <<byte_size(body)::little-unsigned-16>> <> body
  end

  defp properties do
    # stat_count = 0 => 1 stat
    <<
      # max_shots
      255,
      # dark
      0,
      # exits NSWE
      0,
      0,
      0,
      0,
      # restart_on_zap
      0,
      # message len + 58 bytes
      0
    >> <>
      :binary.copy(<<0>>, 58) <>
      <<
        # enter_x
        30,
        # enter_y
        13,
        # time_limit
        0::little-signed-16
      >> <>
      :binary.copy(<<0>>, 16) <>
      <<0::little-signed-16>>
  end

  defp stat(x, y, _char, _color) do
    <<
      x,
      y,
      # step_x, step_y
      0::little-signed-16,
      0::little-signed-16,
      # cycle
      1::little-signed-16,
      # p1, p2, p3
      0,
      0,
      0,
      # follower, leader
      -1::little-signed-16,
      -1::little-signed-16,
      # under_element, under_color
      0,
      0,
      # pointer
      0::little-32,
      # instruction
      0::little-signed-16,
      # bound (no code)
      0::little-signed-16
    >> <> :binary.copy(<<0>>, 8)
  end

  defp rle_encode(tiles), do: rle_encode(tiles, <<>>)

  defp rle_encode([], acc), do: acc

  defp rle_encode([{element, color} | _] = tiles, acc) do
    {count, rest} = run_length(tiles, element, color, 0)
    byte = if count == 256, do: 0, else: count
    rle_encode(rest, acc <> <<byte, element, color>>)
  end

  defp run_length([{e, c} | rest], e, c, n) when n < 256 do
    run_length(rest, e, c, n + 1)
  end

  defp run_length(rest, _e, _c, n), do: {n, rest}

  defp pascal(str, pad_len) do
    bin = :erlang.iolist_to_binary(str)
    len = min(byte_size(bin), pad_len)
    <<len>> <> binary_part(bin, 0, len) <> :binary.copy(<<0>>, pad_len - len)
  end
end
