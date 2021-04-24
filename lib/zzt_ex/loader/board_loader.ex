defmodule ZZTEx.Loader.BoardLoader do
  alias ZZTEx.World.Board
  alias ZZTEx.World.Tile

  alias ZZTEx.Loader.StatusElementLoader

  @zzt_tile_count 1500
  @board_width 60

  import ZZTEx.Loader.Helpers

  @spec load_boards(integer, binary) :: {:ok, list, binary}
  def load_boards(board_count, board_contents) do
    {boards, rest} = do_load_boards([], board_count, board_contents)
    # Board count is 1 + the header value
    {:ok, boards, rest}
  end

  defp do_load_boards(boards, 0, rest), do: {Enum.reverse(boards), rest}

  defp do_load_boards(
         boards,
         count,
         <<size::signed-little-size(16), board::binary-size(size), rest::binary>>
       ) do
    {:ok, board} = do_load_board(board)

    [board | boards]
    |> do_load_boards(count - 1, rest)
  end

  @spec do_load_board(binary) :: {:ok, Board.t()}
  defp do_load_board(<<board_name::binary-size(51), rest::binary>>) do
    with {:ok, tiles, rest} <- do_load_rle([], @zzt_tile_count, rest),
         board_name <- load_fixed_string(board_name),
         {:ok, board} <- do_load_properties(board_name, tiles, rest) do
      {:ok, board}
    end
  end

  defp do_load_rle(tiles, 0, rest) do
    board_tiles =
      tiles
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {tile, i} ->
        x = rem(i, @board_width)
        y = div(i, @board_width)

        {{x, y}, tile}
      end)
      |> Map.new()

    {:ok, board_tiles, rest}
  end

  defp do_load_rle(tiles, remaining, <<count::8, element::8, color::8, rest::binary>>) do
    Enum.reduce(1..count, tiles, fn _, acc ->
      [
        %Tile{
          element: element,
          color: color
        }
        | acc
      ]
    end)
    |> do_load_rle(remaining - count, rest)
  end

  @spec do_load_properties(String.t(), Tile.tiles_t(), binary) :: {:ok, Board.t()}
  def do_load_properties(
        board_name,
        tiles,
        <<
          max_player_shots::8,
          is_dark::8,
          exit_north::8,
          exit_south::8,
          exit_west::8,
          exit_east::8,
          restart_on_zap::8,
          message::binary-size(59),
          player_enter_x::8,
          player_enter_y::8,
          time_limit::signed-little-size(16),
          _unused::binary-size(16),
          status_elements::binary
        >>
      ) do
    {:ok, status_elements} = StatusElementLoader.load_status_elements(status_elements)

    {:ok,
     %Board{
       board_name: board_name,
       tiles: tiles,
       max_player_shots: max_player_shots,
       is_dark: is_dark != 0,
       exit_north: exit_north,
       exit_south: exit_south,
       exit_west: exit_west,
       exit_east: exit_east,
       restart_on_zap: restart_on_zap != 0,
       message: load_fixed_string(message),
       player_enter: {player_enter_x, player_enter_y},
       time_limit: time_limit,
       status_elements: status_elements
     }}
  end
end
