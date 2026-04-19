defmodule ZztEx.Zzt.RenderTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.ZztFixture
  alias ZztEx.Zzt.{Board, Render, Stat, World}

  @width Board.width()

  defp put_tile(tiles, x, y, tile), do: List.replace_at(tiles, (y - 1) * @width + (x - 1), tile)

  defp empty_tiles, do: List.duplicate({0, 0}, @width * Board.height())

  defp cell_at(rows, x, y), do: rows |> Enum.at(y - 1) |> Enum.at(x - 1)

  defp render(tiles, opts \\ []) do
    stats = Keyword.get(opts, :stats, nil)

    binary =
      if stats do
        ZztFixture.world(tiles: tiles, stats: stats)
      else
        ZztFixture.world(tiles: tiles)
      end

    {:ok, world} = World.parse(binary)
    [board] = world.boards
    Render.rows(board, Keyword.take(opts, [:tick, :title_screen?]))
  end

  test "produces 25 rows of 60 cells" do
    rows = render(empty_tiles())

    assert length(rows) == 25
    assert Enum.all?(rows, &(length(&1) == 60))
  end

  test "empty tile renders as blank black cell" do
    rows = render(empty_tiles())
    assert cell_at(rows, 1, 1) == {" ", 7, 0, false}
  end

  test "title_screen? hides the player at stat 0's position" do
    tiles = put_tile(empty_tiles(), 30, 13, {4, 0x1F})

    normal = render(tiles) |> cell_at(30, 13)
    hidden = render(tiles, title_screen?: true) |> cell_at(30, 13)

    assert elem(normal, 0) == <<0x263B::utf8>>
    assert hidden == {" ", 7, 0, false}
  end

  test "empty tiles ignore residual color bytes (town.zzt editor ghosts)" do
    tiles = put_tile(empty_tiles(), 1, 1, {0, 0x73})
    assert cell_at(render(tiles), 1, 1) == {" ", 7, 0, false}
  end

  test "invisible walls render blank regardless of stored color" do
    tiles = put_tile(empty_tiles(), 1, 1, {28, 0x4F})
    assert cell_at(render(tiles), 1, 1) == {" ", 7, 0, false}
  end

  test "decodes foreground and background from the color byte" do
    # Solid (21) with color 0x4F = red bg, white fg
    tiles = put_tile(empty_tiles(), 1, 1, {21, 0x4F})
    {char, fg, bg, blink} = cell_at(render(tiles), 1, 1)

    assert fg == 15
    assert bg == 4
    assert blink == false
    # Solid block glyph
    assert char == <<0x2588::utf8>>
  end

  test "sets blink flag when the high bit of the color byte is set" do
    # 0x8F = blink + fg 15; bg still 0 after masking the blink bit.
    tiles = put_tile(empty_tiles(), 1, 1, {21, 0x8F})
    {_char, fg, bg, blink} = cell_at(render(tiles), 1, 1)

    assert blink == true
    assert fg == 15
    assert bg == 0
  end

  test "pusher glyph follows its stat's step direction" do
    # Pusher (40) facing east.
    tiles = put_tile(empty_tiles(), 10, 5, {40, 0x0F})
    stats = [player_stat(), pusher_stat(10, 5, step_x: 1)]
    {char, _fg, _bg, _blink} = cell_at(render(tiles, stats: stats), 10, 5)
    # CP437 0x10 = ► (U+25BA)
    assert char == <<0x25BA::utf8>>

    stats = [player_stat(), pusher_stat(10, 5, step_x: -1)]
    assert elem(cell_at(render(tiles, stats: stats), 10, 5), 0) == <<0x25C4::utf8>>

    stats = [player_stat(), pusher_stat(10, 5, step_y: -1)]
    assert elem(cell_at(render(tiles, stats: stats), 10, 5), 0) == <<0x25B2::utf8>>

    stats = [player_stat(), pusher_stat(10, 5, step_y: 1)]
    assert elem(cell_at(render(tiles, stats: stats), 10, 5), 0) == <<0x25BC::utf8>>
  end

  test "star cycles through four frames as tick advances" do
    tiles = put_tile(empty_tiles(), 1, 1, {15, 0x0F})
    frames = for t <- 0..3, do: elem(cell_at(render(tiles, tick: t), 1, 1), 0)

    # /, |, \, - in CP437/ASCII
    assert frames == ["/", "|", "\\", "-"]
  end

  test "star cycles foreground color 9..15 independent of stored color" do
    tiles = put_tile(empty_tiles(), 1, 1, {15, 0x0F})
    fgs = for t <- 0..6, do: elem(cell_at(render(tiles, tick: t), 1, 1), 1)
    assert fgs == [9, 10, 11, 12, 13, 14, 15]
  end

  test "line element picks glyph from cardinal neighbors" do
    # Isolated line in the middle of the board → bullet-dot ∙ (0xF9).
    tiles = put_tile(empty_tiles(), 30, 12, {31, 0x0F})
    assert elem(cell_at(render(tiles), 30, 12), 0) == <<0x2219::utf8>>

    # Horizontal run of three lines → middle becomes ═ (0xCD).
    tiles =
      empty_tiles()
      |> put_tile(29, 12, {31, 0x0F})
      |> put_tile(30, 12, {31, 0x0F})
      |> put_tile(31, 12, {31, 0x0F})

    assert elem(cell_at(render(tiles), 30, 12), 0) == <<0x2550::utf8>>
  end

  test "line at the board edge treats the edge as a connector" do
    # A line at the top-left corner sees its N and W neighbors as edges, so
    # the glyph carries segments going up and left → ╝ (CP437 0xBC).
    tiles = put_tile(empty_tiles(), 1, 1, {31, 0x0F})
    assert elem(cell_at(render(tiles), 1, 1), 0) == <<0x255D::utf8>>
  end

  defp player_stat, do: %Stat{x: 30, y: 13}

  defp pusher_stat(x, y, opts) do
    %Stat{
      x: x,
      y: y,
      step_x: Keyword.get(opts, :step_x, 0),
      step_y: Keyword.get(opts, :step_y, 0)
    }
  end

  describe "message overlay" do
    test "centers the message with surrounding spaces on the bottom row" do
      {:ok, world} = World.parse(ZztFixture.world(tiles: empty_tiles()))
      [board] = world.boards

      rows = Render.rows(board, message: {"Hi", 5})

      # " Hi " is 4 chars, so (60 - 4) div 2 = 28 → 1-indexed start col 29.
      assert cell_at(rows, 29, 25) == {" ", 9 + rem(5, 7), 0, false}
      assert cell_at(rows, 30, 25) == {"H", 14, 0, false}
      assert cell_at(rows, 31, 25) == {"i", 14, 0, false}
      assert cell_at(rows, 32, 25) == {" ", 14, 0, false}
    end

    test "foreground cycles by ticks mod 7" do
      {:ok, world} = World.parse(ZztFixture.world(tiles: empty_tiles()))
      [board] = world.boards

      rows_a = Render.rows(board, message: {"X", 7})
      rows_b = Render.rows(board, message: {"X", 8})

      {_char, fg_a, _bg, _blink} = cell_at(rows_a, 30, 25)
      {_char, fg_b, _bg, _blink} = cell_at(rows_b, 30, 25)

      # 7 mod 7 = 0 → fg 9; 8 mod 7 = 1 → fg 10.
      assert fg_a == 9
      assert fg_b == 10
    end

    test "ticks <= 0 skips the overlay" do
      {:ok, world} = World.parse(ZztFixture.world(tiles: empty_tiles()))
      [board] = world.boards

      rows_with = Render.rows(board, message: {"Hi", 5})
      rows_without = Render.rows(board, message: {"Hi", 0})

      refute cell_at(rows_with, 30, 25) == cell_at(rows_without, 30, 25)
      assert cell_at(rows_without, 30, 25) == {" ", 7, 0, false}
    end
  end
end
