defmodule ZztEx.Zzt.AI.BombTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Board, Game, Stat}
  alias ZztEx.Zzt.AI.Bomb

  @bomb 13
  @breakable 23
  @empty 0

  defp blank_tiles do
    for y <- 1..Board.height(), x <- 1..Board.width(), into: %{} do
      {{x, y}, {@empty, 0x0F}}
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

  # Player at (1, 1), bomb stat at (10, 10) with P1 controlling state.
  defp bomb_game(p1, extras \\ []) do
    bomb_stat = %Stat{x: 10, y: 10, cycle: 6, p1: p1}

    tiles =
      Enum.reduce(extras, blank_tiles(), fn {pos, tile}, acc ->
        Map.put(acc, pos, tile)
      end)
      |> Map.put({10, 10}, {@bomb, 0x0F})
      |> Map.put({1, 1}, {4, 0x1F})

    extra_stats = Keyword.get(extras, :stats, [])

    %Game{
      tiles: tiles,
      stats: [%Stat{x: 1, y: 1, cycle: 1}] ++ extra_stats ++ [bomb_stat],
      player: base_player_state(),
      stat_tick: 0
    }
  end

  defp bomb_stat(game), do: List.last(game.stats)

  describe "tick/2" do
    test "disarmed bomb (P1 = 0) is a no-op" do
      game = bomb_game(0)
      final = Bomb.tick(game, length(game.stats) - 1)

      assert bomb_stat(final).p1 == 0
      assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == @bomb
    end

    test "counts down while P1 is in 3..9" do
      game = bomb_game(9)
      final = Bomb.tick(game, length(game.stats) - 1)

      assert bomb_stat(final).p1 == 8
      # Bomb tile is untouched during the beep phase.
      assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == @bomb
    end

    test "P1 = 2 triggers the explosion: paints colored breakables in radius" do
      game = bomb_game(2)
      final = Bomb.tick(game, length(game.stats) - 1)

      assert bomb_stat(final).p1 == 1
      # A cell next to the bomb should now be a colored breakable.
      {elem, color} = Map.fetch!(final.tiles, {11, 10})
      assert elem == @breakable
      assert color in 0x09..0x0F
      # The bomb tile itself is preserved (not paintable — it's neither
      # empty nor breakable).
      assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == @bomb
    end

    test "explosion respects the torch ellipse radius" do
      # TORCH_DX = 8, so (bomb.x + 9, bomb.y) lies outside the blast.
      game = bomb_game(2)
      final = Bomb.tick(game, length(game.stats) - 1)

      # (10+9, 10) squared distance = 81 > 50 → untouched.
      assert Map.fetch!(final.tiles, {19, 10}) |> elem(0) == @empty
      # (10, 10+6) squared distance * 2 = 72 > 50 → untouched.
      assert Map.fetch!(final.tiles, {10, 16}) |> elem(0) == @empty
    end

    test "explosion damages the player when inside the blast" do
      # Player at (9, 10) — one west of bomb, inside the radius.
      game = bomb_game(2)
      player = Enum.at(game.stats, 0)

      tiles =
        game.tiles
        |> Map.put({1, 1}, {@empty, 0x0F})
        |> Map.put({9, 10}, {4, 0x1F})

      game = %{
        game
        | tiles: tiles,
          stats: List.replace_at(game.stats, 0, %Stat{player | x: 9, y: 10})
      }

      bomb_idx = length(game.stats) - 1
      final = Bomb.tick(game, bomb_idx)

      assert final.player.health == 90
    end

    test "P1 = 1 triggers cleanup: painted breakables become empty and stat is removed" do
      # Put the bomb in post-explosion state with breakables around it.
      game = bomb_game(1)

      tiles =
        game.tiles
        |> Map.put({11, 10}, {@breakable, 0x0B})
        |> Map.put({10, 9}, {@breakable, 0x0D})

      game = %{game | tiles: tiles}

      bomb_idx = length(game.stats) - 1
      final = Bomb.tick(game, bomb_idx)

      # Bomb stat removed.
      assert length(final.stats) == length(game.stats) - 1
      # Breakables within range are wiped.
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == @empty
      assert Map.fetch!(final.tiles, {10, 9}) |> elem(0) == @empty
      # Bomb tile is restored to whatever was under (empty in this fixture).
      assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == @empty
    end

    test "walking into an unarmed bomb arms it and blocks the player" do
      # Player at (9, 10), bomb at (10, 10) with P1 = 0.
      bomb_stat = %Stat{x: 10, y: 10, cycle: 6, p1: 0}

      tiles =
        blank_tiles()
        |> Map.put({10, 10}, {@bomb, 0x0F})
        |> Map.put({9, 10}, {4, 0x1F})

      game = %Game{
        tiles: tiles,
        stats: [%Stat{x: 9, y: 10, cycle: 1}, bomb_stat],
        player: base_player_state(),
        stat_tick: 0
      }

      final = Game.move_player(game, 1, 0)

      # Player didn't advance onto the bomb tile.
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {9, 10}
      # Bomb stat now has P1 = 9.
      assert Enum.at(final.stats, 1).p1 == 9
    end

    test "walking into an armed bomb pushes it forward" do
      # Player (9, 10), armed bomb (10, 10), empty tile at (11, 10).
      bomb_stat = %Stat{x: 10, y: 10, cycle: 6, p1: 5}

      tiles =
        blank_tiles()
        |> Map.put({10, 10}, {@bomb, 0x0F})
        |> Map.put({9, 10}, {4, 0x1F})

      game = %Game{
        tiles: tiles,
        stats: [%Stat{x: 9, y: 10, cycle: 1}, bomb_stat],
        player: base_player_state(),
        stat_tick: 0
      }

      final = Game.move_player(game, 1, 0)

      # Bomb shifted east, player followed.
      assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == @bomb
      player = Enum.at(final.stats, 0)
      assert {player.x, player.y} == {10, 10}
      # P1 unchanged by the push.
      assert Enum.at(final.stats, 1).p1 == 5
    end

    test "explosion sends :BOMBED to nearby object" do
      object_code = "@obj\r:BOMBED\r#set bombed\r#end\r"
      obj_stat = %Stat{x: 11, y: 10, cycle: 3, code: object_code}

      game = bomb_game(2, stats: [obj_stat])
      # Place the object tile.
      game = %{game | tiles: Map.put(game.tiles, {11, 10}, {36, 0x0F})}

      bomb_idx = length(game.stats) - 1
      final = Bomb.tick(game, bomb_idx)

      # :BOMBED runs inline during the bomb's explosion so the flag is
      # already set without a separate advance.
      assert Game.flag?(final, "bombed")
    end
  end
end
