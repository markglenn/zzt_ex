defmodule ZZTExWeb.PageLive do
  use ZZTExWeb, :live_view

  alias ZZTEx.World.Board
  alias ZZTEx.Elements.Element
  alias ZZTEx.Elements.ElementType

  # @tick_speed 110
  @tick_speed 1000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        {:ok, world} = ZZTEx.Loader.ZZTFile.load("priv/worlds/TOWN.ZZT")
        Process.send_after(self(), :update, @tick_speed)

        socket
        |> assign(world: world)
        |> assign(board: Enum.at(world.boards, 0))
      else
        socket
        |> assign(board: nil)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("suggest", %{"q" => _query}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:update, %{assigns: assigns} = socket) do
    Process.send_after(self(), :update, @tick_speed)

    board =
      assigns.board
      |> ZZTEx.Game.tick()

    {:noreply, assign(socket, :board, board)}
  end

  def tile(%{board: nil} = assigns, _x, _y), do: ~L""

  def tile(%{board: board} = assigns, x, y) do
    tile = Board.tile_at(board, {x, y})
    status_element = Board.status_at(board, {x, y})

    element =
      tile.element
      |> ElementType.element()

    color =
      element
      |> Element.color(tile)
      |> Integer.to_string(16)
      |> String.pad_leading(2, "0")

    glyph =
      element
      |> Element.glyph(tile, status_element)
      |> ZZTEx.Glyph.to_unicode()

    ~L"""
      <span class="c<%= color %>">&#<%= glyph %>;</span>
    """
  end
end
