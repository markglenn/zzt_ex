defmodule ZztEx.Zzt.AI.ConveyorTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Board, Game, Stat}
  alias ZztEx.Zzt.AI.Conveyor

  @cw 16
  @ccw 17
  @boulder 24

  defp blank_tiles do
    for y <- 1..Board.height(), x <- 1..Board.width(), into: %{} do
      {{x, y}, {0, 0}}
    end
  end

  defp base_player_state do
    %{
      health: 100,
      ammo: 0,
      gems: 0,
      keys: List.duplicate(false, 7),
      torches: 0,
      score: 0,
      energizer_ticks: 0
    }
  end

  # A 3x3 game with a conveyor at (10, 10), one boulder at the given
  # offset, and everything else empty.
  defp conveyor_with_boulder(direction, {bx, by}) do
    conveyor_element = if direction == :cw, do: @cw, else: @ccw
    conveyor_stat = %Stat{x: 10, y: 10, cycle: 2}

    tiles =
      blank_tiles()
      |> Map.put({10, 10}, {conveyor_element, 0x0D})
      |> Map.put({bx, by}, {@boulder, 0x0F})
      |> Map.put({1, 1}, {4, 0x1F})

    %Game{
      tiles: tiles,
      stats: [%Stat{x: 1, y: 1, cycle: 1}, conveyor_stat],
      player: base_player_state(),
      stat_tick: 0
    }
  end

  test "clockwise conveyor rotates a boulder from N to NE" do
    # Boulder north of the center should end up north-east after one CW tick.
    game = conveyor_with_boulder(:cw, {10, 9})

    final = Conveyor.cw_tick(game, 1)

    assert Map.fetch!(final.tiles, {11, 9}) |> elem(0) == @boulder
    # Original slot is empty (chain terminates here, W neighbor at (9,10)
    # is non-pushable empty, so the vacated tile stays clear).
    assert Map.fetch!(final.tiles, {10, 9}) |> elem(0) == 0
  end

  test "counter-clockwise conveyor rotates a boulder from N to NW" do
    game = conveyor_with_boulder(:ccw, {10, 9})

    final = Conveyor.ccw_tick(game, 1)

    assert Map.fetch!(final.tiles, {9, 9}) |> elem(0) == @boulder
    assert Map.fetch!(final.tiles, {10, 9}) |> elem(0) == 0
  end

  test "non-pushable tile (wall) blocks the rotation" do
    # A Normal wall at N stops anything from rotating past it.
    conveyor_stat = %Stat{x: 10, y: 10, cycle: 2}

    tiles =
      blank_tiles()
      |> Map.put({10, 10}, {@cw, 0x0D})
      # Wall at N (10, 9)
      |> Map.put({10, 9}, {22, 0x0E})
      # Boulder at W (9, 10): would try to shift to NW (9, 9) — SW at (9,11)
      # Wait, let me reason: CW moves tile at i to i-1. Position 7 (W at 9,10)
      # moves to position 6 (NW at 9,9). So the boulder should move NW.
      |> Map.put({9, 10}, {@boulder, 0x0F})
      |> Map.put({1, 1}, {4, 0x1F})

    game = %Game{
      tiles: tiles,
      stats: [%Stat{x: 1, y: 1, cycle: 1}, conveyor_stat],
      player: base_player_state(),
      stat_tick: 0
    }

    final = Conveyor.cw_tick(game, 1)

    # Boulder made it to NW (9, 9).
    assert Map.fetch!(final.tiles, {9, 9}) |> elem(0) == @boulder
    # Wall at N is unchanged.
    assert Map.fetch!(final.tiles, {10, 9}) |> elem(0) == 22
  end
end
