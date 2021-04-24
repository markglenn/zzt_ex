defmodule ZZTEx.Game do
  alias ZZTEx.World.Board
  alias ZZTEx.Elements.ElementType
  alias ZZTEx.Elements.Tick

  def tick(%Board{} = board) do
    Enum.reduce(board.status_elements, board, fn status_element, acc ->
      tile = Board.tile_at(board, status_element.location)
      %{element_type: type} = ElementType.element(tile.element)

      Tick.tick(acc, type, status_element)
    end)
  end
end
