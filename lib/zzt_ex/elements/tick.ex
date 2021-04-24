defmodule ZZTEx.Elements.Tick do
  alias ZZTEx.Elements.ElementType
  alias ZZTEx.World.Board
  alias ZZTEx.World.StatusElement
  alias ZZTEx.World.Point

  @spec tick(Board.t(), atom, StatusElement.t()) :: Board.t()
  def tick(%Board{} = board, :lion, %StatusElement{} = status_element) do
    delta =
      if status_element.p1 < Enum.random(0..9) do
        random_direction()
      else
        seek_direction(board, status_element.location)
      end

    location = Point.add(status_element.location, delta)

    tile = board.tiles[location]

    if ElementType.element(tile.element).walkable do
      board
      |> Board.move_status(status_element, location)
      |> elem(0)
    else
      board
    end
  end

  def tick(%Board{} = board, :tiger, %StatusElement{} = status_element) do
    # TODO: Tigers shoot
    tick(board, :lion, status_element)
  end

  def tick(%Board{} = board, :head, %StatusElement{} = status_element),
    do: ZZTEx.Elements.Tick.Centipede.tick(board, status_element)

  def tick(board, _, _), do: board

  # Get a random direction (North, South, East, or West)
  @spec random_direction :: {-1, 0} | {1, 0} | {0, -1} | {0, 1}
  def random_direction,
    do:
      Enum.random([
        {-1, 0},
        {1, 0},
        {0, -1},
        {0, 1}
      ])

  def seek_direction(%Board{} = board, {x, y}) do
    [player | _rest] = board.status_elements
    {player_x, player_y} = player.location

    delta_x =
      if Enum.random(0..1) == 0 || player_y == y do
        signum(player_x, x)
      else
        0
      end

    delta_y =
      if delta_x == 0 do
        signum(player_y, y)
      else
        0
      end

    #  // if World.Info.EnergizerTicks > 0 then begin
    #  //     deltaX := -deltaX;
    #  //     deltaY := -deltaY;
    #  // end;

    {delta_x, delta_y}
  end

  @spec signum(non_neg_integer(), non_neg_integer()) :: -1 | 0 | 1
  def signum(first, first), do: 0
  def signum(first, second) when first > second, do: 1
  def signum(_, _), do: -1
end
