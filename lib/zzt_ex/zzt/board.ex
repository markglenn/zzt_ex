defmodule ZztEx.Zzt.Board do
  @moduledoc """
  A single ZZT board: title, 60x25 tile grid, scalar properties, and stats.

  Boards are stored on disk with a 2-byte little-endian length prefix followed
  by exactly that many bytes of board data. The layout inside is:

    * Pascal-style title (1 length byte + 50 padding bytes)
    * RLE-compressed tile stream for 1500 tiles
    * 88-byte property block (shots, darkness, exits, message, start, timer)
    * 2-byte `stat_count` (0-based: actual stat count is `stat_count + 1`)
    * `stat_count + 1` stat entries
  """

  alias ZztEx.Zzt.{Rle, Stat}

  @width 60
  @height 25
  @tile_count @width * @height

  defstruct title: "",
            tiles: [],
            max_shots: 0,
            dark?: false,
            exit_north: 0,
            exit_south: 0,
            exit_west: 0,
            exit_east: 0,
            restart_on_zap?: false,
            message: "",
            enter_x: 0,
            enter_y: 0,
            time_limit: 0,
            stats: []

  @type tile :: {element :: 0..255, color :: 0..255}

  @type t :: %__MODULE__{
          title: String.t(),
          tiles: [tile()],
          max_shots: 0..255,
          dark?: boolean(),
          exit_north: 0..255,
          exit_south: 0..255,
          exit_west: 0..255,
          exit_east: 0..255,
          restart_on_zap?: boolean(),
          message: String.t(),
          enter_x: 0..255,
          enter_y: 0..255,
          time_limit: integer(),
          stats: [Stat.t()]
        }

  @doc "Board width in tiles (always 60 in stock ZZT)."
  def width, do: @width
  @doc "Board height in tiles (always 25 in stock ZZT)."
  def height, do: @height

  @doc """
  Parse a length-prefixed board from the head of `binary`.

  Returns `{:ok, board, rest}` or `{:error, reason}`. `rest` is the remaining
  input after this board's bytes are consumed.
  """
  @spec parse(binary()) :: {:ok, t(), binary()} | {:error, term()}
  def parse(<<size::little-unsigned-16, body::binary-size(size), rest::binary>>) do
    with {:ok, board} <- parse_body(body) do
      {:ok, board, rest}
    end
  end

  def parse(_), do: {:error, :truncated_board}

  defp parse_body(<<
         title_len,
         title::binary-size(50),
         after_title::binary
       >>) do
    {tiles, after_tiles} = Rle.decode(after_title, @tile_count)

    with {:ok, props, after_props} <- parse_properties(after_tiles),
         {:ok, stats} <- parse_stats(after_props, props.stat_count + 1) do
      {:ok,
       %__MODULE__{
         title: pascal_string(title, title_len),
         tiles: tiles,
         max_shots: props.max_shots,
         dark?: props.dark?,
         exit_north: props.exit_north,
         exit_south: props.exit_south,
         exit_west: props.exit_west,
         exit_east: props.exit_east,
         restart_on_zap?: props.restart_on_zap?,
         message: props.message,
         enter_x: props.enter_x,
         enter_y: props.enter_y,
         time_limit: props.time_limit,
         stats: resolve_bound_refs(stats)
       }}
    end
  end

  defp parse_body(_), do: {:error, :truncated_board_body}

  # BoardOpen's second pass (GAME.PAS:261-264): any stat loaded with
  # `DataLen < 0` reuses the program of stat `-DataLen`. In our struct
  # that's `bound` + `code`. We normalise so callers only ever see a
  # non-negative bound and a real code binary — matching what the
  # reference's post-load pass leaves behind.
  defp resolve_bound_refs(stats) do
    stats_tuple = List.to_tuple(stats)

    Enum.map(stats, fn stat ->
      if stat.bound < 0 do
        case fetch_shared(stats_tuple, -stat.bound) do
          nil -> stat
          src -> %{stat | code: src.code, bound: byte_size(src.code)}
        end
      else
        stat
      end
    end)
  end

  defp fetch_shared(stats_tuple, idx) when idx >= 0 and idx < tuple_size(stats_tuple),
    do: elem(stats_tuple, idx)

  defp fetch_shared(_, _), do: nil

  defp parse_properties(<<
         max_shots,
         dark,
         exit_north,
         exit_south,
         exit_west,
         exit_east,
         restart_on_zap,
         message_len,
         message::binary-size(58),
         enter_x,
         enter_y,
         time_limit::little-signed-16,
         _unused::binary-size(16),
         stat_count::little-signed-16,
         rest::binary
       >>) do
    {:ok,
     %{
       max_shots: max_shots,
       dark?: dark != 0,
       exit_north: exit_north,
       exit_south: exit_south,
       exit_west: exit_west,
       exit_east: exit_east,
       restart_on_zap?: restart_on_zap != 0,
       message: pascal_string(message, message_len),
       enter_x: enter_x,
       enter_y: enter_y,
       time_limit: time_limit,
       stat_count: stat_count
     }, rest}
  end

  defp parse_properties(_), do: {:error, :truncated_board_properties}

  defp parse_stats(binary, count), do: parse_stats(binary, count, [])

  defp parse_stats(_binary, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_stats(binary, remaining, acc) do
    {stat, rest} = Stat.parse(binary)
    parse_stats(rest, remaining - 1, [stat | acc])
  rescue
    _ -> {:error, :truncated_stat}
  end

  defp pascal_string(binary, length) do
    length = min(length, byte_size(binary))
    binary |> binary_part(0, length) |> :binary.bin_to_list() |> List.to_string()
  end

  @doc """
  Look up a tile at 1-indexed `{x, y}` (matching ZZT's coordinate system).
  Returns `{element, color}` or `nil` if out of range.
  """
  @spec tile_at(t(), 1..60, 1..25) :: tile() | nil
  def tile_at(%__MODULE__{tiles: tiles}, x, y)
      when x in 1..@width and y in 1..@height do
    Enum.at(tiles, (y - 1) * @width + (x - 1))
  end

  def tile_at(_, _, _), do: nil
end
