defmodule ZztEx.Zzt.GameTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Board, Game, Stat}

  defp base_player_state(overrides) do
    Map.merge(
      %{
        health: 100,
        ammo: 0,
        gems: 0,
        keys: List.duplicate(false, 7),
        torches: 0,
        score: 0,
        energizer_ticks: 0
      },
      Map.new(overrides)
    )
  end

  defp blank_game(opts) do
    {px, py} = Keyword.get(opts, :player_xy, {10, 10})
    walls = Keyword.get(opts, :walls, [])
    player_overrides = Keyword.get(opts, :player, %{})

    tiles =
      for y <- 1..Board.height(), x <- 1..Board.width(), into: %{} do
        {{x, y}, {0, 0x0F}}
      end

    tiles =
      walls
      |> Enum.reduce(tiles, fn pos, acc -> Map.put(acc, pos, {22, 0x0E}) end)
      |> Map.put({px, py}, {4, 0x1F})

    %Game{
      tiles: tiles,
      stats: [%Stat{x: px, y: py, cycle: 1}],
      player: base_player_state(player_overrides),
      stat_tick: 0
    }
  end

  describe "move_player/3" do
    test "moves the player onto a walkable tile" do
      game = blank_game(player_xy: {10, 10})
      final = Game.move_player(game, 1, 0)

      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {11, 10}
      # Old tile restored to whatever was underneath (empty).
      assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == 0
      # New tile now shows the player element.
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 4
    end

    test "blocks on non-walkable tiles" do
      game = blank_game(player_xy: {10, 10}, walls: [{11, 10}])
      final = Game.move_player(game, 1, 0)

      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {10, 10}
    end

    test "doesn't move off the board" do
      game = blank_game(player_xy: {60, 10})
      final = Game.move_player(game, 1, 0)

      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {60, 10}
    end

    test "dead player can't move" do
      game = blank_game(player_xy: {10, 10}, player: %{health: 0})
      final = Game.move_player(game, 1, 0)

      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {10, 10}
    end
  end
end
