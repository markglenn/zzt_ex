defmodule ZztEx.Zzt.World do
  @moduledoc """
  A ZZT world — the top-level structure of a `.zzt` file.

  The on-disk layout is a 512-byte header followed by `board_count` boards,
  each length-prefixed. The header field `board_count` is stored as
  `n - 1` (a world with 1 board stores `0`), which this parser normalises.
  """

  alias ZztEx.Zzt.Board

  @header_size 512
  @magic -1

  defstruct name: "",
            ammo: 0,
            gems: 0,
            keys: [false, false, false, false, false, false, false],
            health: 100,
            current_board: 0,
            torches: 0,
            torch_cycles: 0,
            energizer_cycles: 0,
            score: 0,
            flags: [],
            boards: []

  @type t :: %__MODULE__{
          name: String.t(),
          ammo: integer(),
          gems: integer(),
          keys: [boolean()],
          health: integer(),
          current_board: non_neg_integer(),
          torches: integer(),
          torch_cycles: integer(),
          energizer_cycles: integer(),
          score: integer(),
          flags: [String.t()],
          boards: [Board.t()]
        }

  @doc """
  Read a world from disk.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    case File.read(path) do
      {:ok, binary} -> parse(binary)
      {:error, reason} -> {:error, {:io, reason}}
    end
  end

  @doc """
  Parse a world from a raw binary. Accepts stock ZZT worlds; Super ZZT and
  savegame (`.sav`) files are intentionally out of scope for now.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(<<header::binary-size(@header_size), rest::binary>>) do
    with {:ok, meta} <- parse_header(header),
         {:ok, boards} <- parse_boards(rest, meta.board_count) do
      {:ok,
       %__MODULE__{
         name: meta.name,
         ammo: meta.ammo,
         gems: meta.gems,
         keys: meta.keys,
         health: meta.health,
         current_board: meta.current_board,
         torches: meta.torches,
         torch_cycles: meta.torch_cycles,
         energizer_cycles: meta.energizer_cycles,
         score: meta.score,
         flags: meta.flags,
         boards: boards
       }}
    end
  end

  def parse(_), do: {:error, :truncated_header}

  defp parse_header(<<
         magic::little-signed-16,
         board_count_minus_one::little-signed-16,
         ammo::little-signed-16,
         gems::little-signed-16,
         keys::binary-size(7),
         health::little-signed-16,
         current_board::little-signed-16,
         torches::little-signed-16,
         torch_cycles::little-signed-16,
         energizer_cycles::little-signed-16,
         _unused1::little-signed-16,
         score::little-signed-16,
         name_len,
         name::binary-size(20),
         rest::binary
       >>)
       when magic == @magic do
    {flags, _rest} = parse_flags(rest, 10)

    {:ok,
     %{
       name: pascal_string(name, name_len),
       ammo: ammo,
       gems: gems,
       keys: for(<<b <- keys>>, do: b != 0),
       health: health,
       current_board: current_board,
       torches: torches,
       torch_cycles: torch_cycles,
       energizer_cycles: energizer_cycles,
       score: score,
       flags: flags,
       board_count: board_count_minus_one + 1
     }}
  end

  defp parse_header(_), do: {:error, :bad_world_magic}

  defp parse_flags(binary, count), do: parse_flags(binary, count, [])

  defp parse_flags(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp parse_flags(<<len, data::binary-size(20), rest::binary>>, remaining, acc) do
    parse_flags(rest, remaining - 1, [pascal_string(data, len) | acc])
  end

  defp parse_boards(binary, count), do: parse_boards(binary, count, [])

  defp parse_boards(_binary, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_boards(binary, remaining, acc) do
    case Board.parse(binary) do
      {:ok, board, rest} -> parse_boards(rest, remaining - 1, [board | acc])
      {:error, _} = err -> err
    end
  end

  defp pascal_string(binary, length) do
    length = min(length, byte_size(binary))
    binary |> binary_part(0, length) |> :binary.bin_to_list() |> List.to_string()
  end

  @doc """
  Return board at `index` (0-indexed), or `nil`.
  """
  @spec board(t(), non_neg_integer()) :: Board.t() | nil
  def board(%__MODULE__{boards: boards}, index) when index >= 0 do
    Enum.at(boards, index)
  end
end
