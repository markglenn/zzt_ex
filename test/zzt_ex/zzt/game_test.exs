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

    test "picks up ammo and walks onto the emptied tile" do
      game = blank_game(player_xy: {10, 10})
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {5, 0x03})}

      final = Game.move_player(game, 1, 0)

      assert final.player.ammo == 5
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {11, 10}
    end

    test "picks up gem and gains health, score, and gem count" do
      game = blank_game(player_xy: {10, 10}, player: %{health: 50, score: 5, gems: 0})
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {7, 0x0B})}

      final = Game.move_player(game, 1, 0)

      assert final.player.gems == 1
      assert final.player.health == 51
      assert final.player.score == 15
    end

    test "picks up energizer and starts the 75-tick timer" do
      game = blank_game(player_xy: {10, 10})
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {14, 0x05})}

      final = Game.move_player(game, 1, 0)

      assert final.player.energizer_ticks == 75
    end

    test "picks up a key if not already held" do
      game = blank_game(player_xy: {10, 10})
      # Color 0x09 = light blue = slot 0.
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {8, 0x09})}

      final = Game.move_player(game, 1, 0)
      assert Enum.at(final.player.keys, 0) == true
    end

    test "bumping a door with the matching key unlocks and consumes it" do
      keys = List.replace_at(List.duplicate(false, 7), 3, true)
      game = blank_game(player_xy: {10, 10}, player: %{keys: keys})
      # Door color 0x4C: high nibble 4 → slot = (4 mod 8) - 1 = 3 (red key).
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {9, 0x4C})}

      final = Game.move_player(game, 1, 0)

      assert Enum.at(final.player.keys, 3) == false
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {11, 10}
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 4
    end

    test "locked door blocks and preserves the key" do
      game = blank_game(player_xy: {10, 10})
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {9, 0x4C})}

      final = Game.move_player(game, 1, 0)

      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {10, 10}
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 9
    end

    test "chopping a forest clears the tile and the player moves through" do
      game = blank_game(player_xy: {10, 10})
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {20, 0x20})}

      final = Game.move_player(game, 1, 0)

      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 4
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {11, 10}
    end

    test "invisible wall reveals itself and blocks the player" do
      game = blank_game(player_xy: {10, 10})
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {28, 0x4F})}

      final = Game.move_player(game, 1, 0)

      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {10, 10}
      {element, _color} = Map.fetch!(final.tiles, {11, 10})
      # Revealed as Normal wall.
      assert element == 22
    end

    test "water splashes but blocks the player" do
      game = blank_game(player_xy: {10, 10})
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {19, 0x9F})}

      final = Game.move_player(game, 1, 0)
      player = Enum.at(final.stats, 0)

      # Water is walkable generically but WaterTouch blocks the player.
      assert {player.x, player.y} == {10, 10}
    end

    test "walking into a lion deals 10 damage and kills the lion" do
      game =
        blank_game(player_xy: {10, 10}, player: %{health: 100})
        |> then(fn g ->
          %{g | tiles: Map.put(g.tiles, {11, 10}, {41, 0x0C})}
        end)

      lion_stat = %Stat{x: 11, y: 10, cycle: 3, p1: 0}
      game = %{game | stats: game.stats ++ [lion_stat]}

      final = Game.move_player(game, 1, 0)

      assert final.player.health == 90
      # Lion stat is gone; player occupies the tile.
      assert length(final.stats) == 1
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {11, 10}
    end

    test "energized player kills lion without damage, scores bounty" do
      game =
        blank_game(
          player_xy: {10, 10},
          player: %{health: 100, energizer_ticks: 50, score: 0}
        )
        |> then(fn g ->
          %{g | tiles: Map.put(g.tiles, {11, 10}, {41, 0x0C})}
        end)

      lion_stat = %Stat{x: 11, y: 10, cycle: 3, p1: 0}
      game = %{game | stats: game.stats ++ [lion_stat]}

      final = Game.move_player(game, 1, 0)

      assert final.player.health == 100
      # Lion is worth 1 point.
      assert final.player.score == 1
      assert length(final.stats) == 1
    end
  end
end
