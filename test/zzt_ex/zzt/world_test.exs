defmodule ZztEx.Zzt.WorldTest do
  use ExUnit.Case, async: true

  alias ZztEx.Test.ZztFixture
  alias ZztEx.Zzt.{Board, World}

  test "parses a synthetic world with one empty board" do
    binary = ZztFixture.world(name: "HELLO", board_title: "Opening")
    assert {:ok, world} = World.parse(binary)

    assert world.name == "HELLO"
    assert world.health == 100
    assert length(world.boards) == 1

    [board] = world.boards
    assert board.title == "Opening"
    assert length(board.tiles) == Board.width() * Board.height()
    assert Enum.all?(board.tiles, &(&1 == {0, 0}))

    [player] = board.stats
    assert {player.x, player.y} == {30, 13}
  end

  test "places custom tiles in row-major order" do
    tiles = List.duplicate({0, 0}, 1500)
    # Drop a solid wall (element 21, color 0x0F) at (1, 1) — index 0
    tiles = List.replace_at(tiles, 0, {21, 0x0F})
    # And at (5, 2) — index (2-1)*60 + (5-1) = 64
    tiles = List.replace_at(tiles, 64, {22, 0x0E})

    binary = ZztFixture.world(tiles: tiles)
    assert {:ok, world} = World.parse(binary)
    [board] = world.boards

    assert Board.tile_at(board, 1, 1) == {21, 0x0F}
    assert Board.tile_at(board, 5, 2) == {22, 0x0E}
    assert Board.tile_at(board, 60, 25) == {0, 0}
  end

  test "rejects binaries with the wrong magic" do
    <<_magic::little-signed-16, rest::binary>> = ZztFixture.world()
    bad = <<0::little-signed-16, rest::binary>>
    assert {:error, :bad_world_magic} = World.parse(bad)
  end

  test "rejects truncated input" do
    assert {:error, :truncated_header} = World.parse(<<0, 1, 2>>)
  end
end
