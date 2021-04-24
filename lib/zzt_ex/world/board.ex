defmodule ZZTEx.World.Board do
  alias ZZTEx.World.{Point, StatusElement, Tile}

  defstruct [
    :board_name,
    :tiles,
    :max_player_shots,
    :is_dark,
    :exit_north,
    :exit_south,
    :exit_west,
    :exit_east,
    :restart_on_zap,
    :message,
    :player_enter,
    :time_limit,
    :status_elements
  ]

  @type t :: %__MODULE__{
          board_name: String.t(),
          tiles: Tile.tiles_t(),
          max_player_shots: arity,
          is_dark: boolean,
          exit_north: arity,
          exit_south: arity,
          exit_west: arity,
          exit_east: arity,
          restart_on_zap: boolean,
          message: String.t(),
          player_enter: Point.t(),
          time_limit: integer(),
          status_elements: [StatusElement.t()]
        }

  @spec tile_at(t(), Point.t()) :: Tile.t()
  def tile_at(%__MODULE__{tiles: tiles}, point), do: tiles[point]

  @spec status_at(Board.t(), Point.t()) :: StatusElement.t()
  def status_at(%__MODULE__{status_elements: status_elements}, point) do
    status_elements
    |> Enum.find(&(&1.location == point))
  end

  @spec index_of(Board.t(), StatusElement.t()) :: nil | non_neg_integer
  def index_of(%__MODULE__{status_elements: status_elements}, %StatusElement{
        location: location
      }) do
    status_elements
    |> Enum.find_index(&(&1.location == location))
  end

  @spec move_status(t(), StatusElement.t(), Point.t()) :: {Board.t(), StatusElement.t()}
  def move_status(%__MODULE__{tiles: tiles} = board, status_element, point) do
    replacement_tile = board.tiles[status_element.location]
    new_tile = board.tiles[point]

    idx = index_of(board, status_element)

    old_tile = %Tile{element: status_element.under_id, color: status_element.under_color}

    old_point = status_element.location
    tiles = %{tiles | point => replacement_tile, old_point => old_tile}

    status_element = %{
      status_element
      | under_id: new_tile.element,
        under_color: new_tile.color,
        location: point
    }

    status_elements =
      board.status_elements
      |> List.replace_at(idx, status_element)

    {%{board | tiles: tiles, status_elements: status_elements}, status_element}
  end
end
