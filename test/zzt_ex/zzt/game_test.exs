defmodule ZztEx.Zzt.GameTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Board, Game, Stat, World}

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

  describe "board transitions" do
    # Tiny two-board world: board 0 is a stub title, board 1 has a
    # player near the east edge and an `exit_east` pointing to board 2,
    # which is empty except for a lone player stat.
    defp two_board_game(exit_dir, exit_target) do
      tiles0 = List.duplicate({0, 0x0F}, 1500)
      board0 = %Board{title: "Title", tiles: tiles0, stats: [%Stat{x: 1, y: 1}]}

      b1_tiles =
        tiles0
        |> List.replace_at(row_major(60, 13), {4, 0x1F})

      b1_exits =
        Map.put(
          %{
            exit_north: 0,
            exit_south: 0,
            exit_west: 0,
            exit_east: 0
          },
          exit_dir,
          exit_target
        )

      board1 =
        struct(
          Board,
          [
            title: "A",
            tiles: b1_tiles,
            stats: [%Stat{x: 60, y: 13, cycle: 1}]
          ] ++ Map.to_list(b1_exits)
        )

      b2_tiles =
        tiles0
        |> List.replace_at(row_major(1, 13), {4, 0x1F})

      board2 = %Board{title: "B", tiles: b2_tiles, stats: [%Stat{x: 1, y: 13, cycle: 1}]}

      world = %World{
        name: "T",
        health: 100,
        current_board: 1,
        boards: [board0, board1, board2]
      }

      Game.new(world, 1)
    end

    defp row_major(x, y), do: (y - 1) * 60 + (x - 1)

    test "walking off the east edge transitions to the neighbor board" do
      game = two_board_game(:exit_east, 2)

      final = Game.move_player(game, 1, 0)

      assert final.board_index == 2
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {1, 13}
    end

    test "no neighbor on that edge: player stays put" do
      game = two_board_game(:exit_east, 0)

      final = Game.move_player(game, 1, 0)

      assert final.board_index == 1
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {60, 13}
    end

    test "pushes a boulder out of the way and walks onto the vacated tile" do
      game = blank_game(player_xy: {10, 10})
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {24, 0x0F})}

      final = Game.move_player(game, 1, 0)

      # Boulder pushed from (11, 10) to (12, 10); player now occupies (11, 10).
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {11, 10}
      assert Map.fetch!(final.tiles, {12, 10}) |> elem(0) == 24
    end

    test "pushing a chain of boulders shoves the whole column" do
      game = blank_game(player_xy: {10, 10})

      game = %{
        game
        | tiles:
            Enum.reduce(11..13, game.tiles, fn x, acc -> Map.put(acc, {x, 10}, {24, 0x0F}) end)
      }

      final = Game.move_player(game, 1, 0)

      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {11, 10}
      assert Map.fetch!(final.tiles, {12, 10}) |> elem(0) == 24
      assert Map.fetch!(final.tiles, {13, 10}) |> elem(0) == 24
      assert Map.fetch!(final.tiles, {14, 10}) |> elem(0) == 24
    end

    test "boulder blocked against a wall stays put and blocks the player" do
      game = blank_game(player_xy: {10, 10}, walls: [{12, 10}])
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {24, 0x0F})}

      final = Game.move_player(game, 1, 0)

      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {10, 10}
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 24
    end

    test "NS slider is only pushable along its axis" do
      game = blank_game(player_xy: {10, 10})
      # Slider NS west of the player; pushing east should NOT move it.
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {25, 0x0F})}

      east_final = Game.move_player(game, 1, 0)
      assert Map.fetch!(east_final.tiles, {11, 10}) |> elem(0) == 25
      assert Enum.at(east_final.stats, 0).x == 10

      # But bumping it south (dy = 1) DOES push.
      game2 = blank_game(player_xy: {10, 10})
      game2 = %{game2 | tiles: Map.put(game2.tiles, {10, 11}, {25, 0x0F})}
      south_final = Game.move_player(game2, 0, 1)

      assert Map.fetch!(south_final.tiles, {10, 12}) |> elem(0) == 25
      assert Enum.at(south_final.stats, 0).y == 11
    end

    test "pushing a gem into a wall crushes it" do
      game = blank_game(player_xy: {10, 10}, walls: [{12, 10}])
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {7, 0x0B})}

      final = Game.move_player(game, 1, 0)

      # Gem is destroyed (pushed into wall), leaving empty; player slides in.
      # Wait — the gem is destructible so push damages it → tile becomes
      # empty; player moves onto it.
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == 4
      assert Enum.at(final.stats, 0) |> then(&{&1.x, &1.y}) == {11, 10}
    end

    test "player inventory carries over into the new board" do
      game =
        two_board_game(:exit_east, 2)
        |> Map.update!(:player, &%{&1 | ammo: 42, gems: 3, score: 99})

      final = Game.move_player(game, 1, 0)

      assert final.player.ammo == 42
      assert final.player.gems == 3
      assert final.player.score == 99
    end

    test "entry tile touch proc fires — walking east into a gem picks it up" do
      tiles0 = List.duplicate({0, 0x0F}, 1500)
      board0 = %Board{title: "T", tiles: tiles0, stats: [%Stat{x: 1, y: 1}]}

      b1_tiles = List.replace_at(tiles0, row_major(60, 13), {4, 0x1F})

      board1 =
        %Board{
          title: "A",
          tiles: b1_tiles,
          stats: [%Stat{x: 60, y: 13, cycle: 1}],
          exit_east: 2
        }

      b2_tiles =
        tiles0
        |> List.replace_at(row_major(10, 10), {4, 0x1F})
        |> List.replace_at(row_major(1, 13), {7, 0x0B})

      board2 = %Board{title: "B", tiles: b2_tiles, stats: [%Stat{x: 10, y: 10, cycle: 1}]}

      world = %World{name: "T", health: 100, current_board: 1, boards: [board0, board1, board2]}

      game = Game.new(world, 1) |> Map.update!(:player, &%{&1 | gems: 0})

      final = Game.move_player(game, 1, 0)

      # Gem picked up on the seam; player stands on the vacated tile.
      assert final.board_index == 2
      assert final.player.gems == 1
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {1, 13}
    end
  end

  describe "passage_teleport/3" do
    # Two-board world with a blue passage (color 0x01) on each board.
    # Walking into the one on board 1 should teleport to the one on
    # board 2 and vice versa, preserving inventory.
    defp passage_world do
      tiles0 = List.duplicate({0, 0x0F}, 1500)
      board0 = %Board{title: "T", tiles: tiles0, stats: [%Stat{x: 1, y: 1}]}

      b1_tiles =
        tiles0
        |> List.replace_at(row_major(10, 10), {4, 0x1F})
        |> List.replace_at(row_major(11, 10), {11, 0x01})

      # p3 on the passage stat = destination board index (2).
      passage1_stat = %Stat{x: 11, y: 10, cycle: 0, p3: 2}

      board1 = %Board{
        title: "One",
        tiles: b1_tiles,
        stats: [%Stat{x: 10, y: 10, cycle: 1}, passage1_stat]
      }

      b2_tiles =
        tiles0
        |> List.replace_at(row_major(20, 20), {4, 0x1F})
        |> List.replace_at(row_major(5, 5), {11, 0x01})

      passage2_stat = %Stat{x: 5, y: 5, cycle: 0, p3: 1}

      board2 = %Board{
        title: "Two",
        tiles: b2_tiles,
        stats: [%Stat{x: 20, y: 20, cycle: 1}, passage2_stat]
      }

      %World{name: "T", health: 100, current_board: 1, boards: [board0, board1, board2]}
    end

    test "walking into a passage teleports to the matching-color passage" do
      world = passage_world()
      game = Game.new(world, 1)

      final = Game.move_player(game, 1, 0)

      assert final.board_index == 2
      player = Enum.at(final.stats, 0)
      # Landed on board 2's matching passage at (5, 5).
      assert {player.x, player.y} == {5, 5}
    end

    test "teleport preserves player inventory" do
      world = passage_world()

      game =
        Game.new(world, 1)
        |> Map.update!(:player, &%{&1 | score: 77, torches: 3})

      final = Game.move_player(game, 1, 0)

      assert final.player.score == 77
      assert final.player.torches == 3
    end
  end

  describe "scroll touch" do
    test "walking into a scroll parks its text on pending_scroll and removes the stat" do
      game = blank_game(player_xy: {10, 10})

      code = "@Sign\rHello from a scroll."

      game = %{
        game
        | tiles: Map.put(game.tiles, {11, 10}, {10, 0x0F}),
          stats:
            game.stats ++
              [%Stat{x: 11, y: 10, cycle: 0, code: code}]
      }

      final = Game.move_player(game, 1, 0)

      assert final.pending_scroll == %{
               title: "Sign",
               lines: ["Hello from a scroll."],
               line_pos: 1
             }

      # Scroll stat removed, player walked onto the vacated tile.
      assert length(final.stats) == 1
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {11, 10}
    end

    test "advance/1 no-ops while a scroll is pending" do
      game =
        blank_game(player_xy: {10, 10})
        |> Map.put(:pending_scroll, %{title: "T", lines: ["x"]})

      assert Game.advance(game) == game
    end

    test "dismiss_scroll clears the modal" do
      game =
        blank_game(player_xy: {10, 10})
        |> Map.put(:pending_scroll, %{title: "T", lines: ["x"], line_pos: 1})

      assert Game.dismiss_scroll(game).pending_scroll == nil
    end

    test "scroll_cursor moves line_pos and clamps to the line count" do
      lines = ~w(one two three)
      game =
        blank_game(player_xy: {10, 10})
        |> Map.put(:pending_scroll, %{title: "T", lines: lines, line_pos: 1})

      # Down: 1 -> 2 -> 3 -> clamp at 3.
      game = Game.scroll_cursor(game, 1)
      assert game.pending_scroll.line_pos == 2
      game = Game.scroll_cursor(game, 1)
      assert game.pending_scroll.line_pos == 3
      game = Game.scroll_cursor(game, 1)
      assert game.pending_scroll.line_pos == 3

      # Up: 3 -> 2 -> 1 -> clamp at 1.
      game = Game.scroll_cursor(game, -10)
      assert game.pending_scroll.line_pos == 1
    end
  end
end
