defmodule ZztEx.Zzt.AI.CentipedeTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Board, Game, Stat}
  alias ZztEx.Zzt.AI.Centipede

  @head 44
  @segment 45

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  # Build a centipede game inline: player at `player_xy`, and a chain
  # of length `length`, all at y=head_y, with the head at head_x and
  # segments marching east.
  defp centipede_game(opts) do
    player_xy = Keyword.fetch!(opts, :player_xy)
    length = Keyword.get(opts, :length, 3)
    head_xy = Keyword.get(opts, :head_xy, {20, 10})
    step = Keyword.get(opts, :step, {-1, 0})
    p1 = Keyword.get(opts, :p1, 0)

    {head_x, head_y} = head_xy
    {sx, sy} = step

    tiles =
      for y <- 1..Board.height(), x <- 1..Board.width(), into: %{} do
        {{x, y}, {0, 0x0F}}
      end

    # Place head + segments east of the head on the same row.
    chain_positions = for i <- 0..(length - 1), do: {head_x + i, head_y}

    tiles_with_chain =
      chain_positions
      |> Enum.with_index()
      |> Enum.reduce(tiles, fn {{x, y}, idx}, acc ->
        element = if idx == 0, do: @head, else: @segment
        Map.put(acc, {x, y}, {element, 0x0B})
      end)
      |> Map.put(player_xy, {4, 0x1F})

    # Stat 0 = player, stats 1..n = centipede chain (head first)
    player_stat = %Stat{x: elem(player_xy, 0), y: elem(player_xy, 1), cycle: 1}

    chain_stats =
      chain_positions
      |> Enum.with_index()
      |> Enum.map(fn {{x, y}, idx} ->
        leader = if idx == 0, do: -1, else: idx
        follower = if idx == length - 1, do: -1, else: idx + 2

        %Stat{
          x: x,
          y: y,
          cycle: if(idx == 0, do: 2, else: 0),
          step_x: if(idx == 0, do: sx, else: 0),
          step_y: if(idx == 0, do: sy, else: 0),
          p1: p1,
          leader: leader,
          follower: follower
        }
      end)

    %Game{
      tiles: tiles_with_chain,
      stats: [player_stat | chain_stats],
      player: %{
        health: 100,
        ammo: 0,
        gems: 0,
        keys: List.duplicate(false, 7),
        torches: 0,
        score: 0,
        energizer_ticks: 0
      },
      stat_tick: 0
    }
  end

  test "head moves and each segment slides into its leader's old position" do
    # Chain at (20,10), (21,10), (22,10) heading west; after one tick the
    # head is at (19,10) and each segment has shifted one tile west.
    game = centipede_game(player_xy: {5, 5}, length: 3, head_xy: {20, 10}, step: {-1, 0})

    final = Centipede.tick(game, 1)

    head = Enum.at(final.stats, 1)
    seg1 = Enum.at(final.stats, 2)
    seg2 = Enum.at(final.stats, 3)

    assert {head.x, head.y} == {19, 10}
    assert {seg1.x, seg1.y} == {20, 10}
    assert {seg2.x, seg2.y} == {21, 10}

    # The tile the tail just vacated is empty again.
    assert Map.fetch!(final.tiles, {22, 10}) |> elem(0) == 0
  end

  test "blocked head rotates to a perpendicular open direction" do
    # Head heading west into a wall; north/south are open. One of the
    # rotations has to land the head on a walkable tile.
    game = centipede_game(player_xy: {5, 5}, length: 2, head_xy: {20, 10}, step: {-1, 0})
    game = %{game | tiles: Map.put(game.tiles, {19, 10}, {22, 0x0E})}

    final = Centipede.tick(game, 1)
    head = Enum.at(final.stats, 1)

    # Head should have turned onto one of the vertical neighbors, not
    # stayed at (20, 10). The segment behind follows into (20, 10).
    assert {head.x, head.y} in [{20, 9}, {20, 11}]
  end

  test "fully blocked chain reverses: tail becomes the new head" do
    # Head at (20,10), segment at (21,10), tail at (22,10). Wall the
    # head in from N/S/W and keep the tail's east side open — but the
    # tail doesn't try to move, only the head does, so with every
    # direction around the head blocked the whole chain must flip.
    game = centipede_game(player_xy: {5, 5}, length: 3, head_xy: {20, 10}, step: {-1, 0})

    walls = [{19, 10}, {20, 9}, {20, 11}]

    game =
      Enum.reduce(walls, game, fn pos, acc ->
        %{acc | tiles: Map.put(acc.tiles, pos, {22, 0x0E})}
      end)

    final = Centipede.tick(game, 1)

    # Tile at original head position (20,10) is now a segment.
    assert Map.fetch!(final.tiles, {20, 10}) |> elem(0) == @segment
    # Tile at original tail position (22,10) is now a head.
    assert Map.fetch!(final.tiles, {22, 10}) |> elem(0) == @head

    # Links flipped: stat for old tail now has leader = -1.
    new_head_stat = Enum.find(final.stats, fn s -> s.x == 22 and s.y == 10 end)
    assert new_head_stat.leader == -1
  end

  test "head reconstructs its chain from adjacent segments with unset links" do
    # Stock ZZT saves centipedes with every leader/follower set to -1.
    # Build that scenario and verify the first tick drags the whole chain.
    game = centipede_game(player_xy: {5, 5}, length: 3, head_xy: {20, 10}, step: {-1, 0})

    broken_stats =
      game.stats
      |> Enum.with_index()
      |> Enum.map(fn
        {stat, 0} -> stat
        {stat, _} -> %Stat{stat | follower: -1, leader: -1}
      end)

    game = %{game | stats: broken_stats}

    final = Centipede.tick(game, 1)

    head = Enum.at(final.stats, 1)
    seg1 = Enum.at(final.stats, 2)
    seg2 = Enum.at(final.stats, 3)

    assert {head.x, head.y} == {19, 10}
    assert {seg1.x, seg1.y} == {20, 10}
    assert {seg2.x, seg2.y} == {21, 10}
  end

  test "head attacking the player dies and promotes the follower to head" do
    # Lone player to the head's west; surround head with walls except
    # for the player-facing direction so the head must step into them.
    game = centipede_game(player_xy: {19, 10}, length: 2, head_xy: {20, 10}, step: {-1, 0})

    walls = [{20, 9}, {20, 11}]

    game =
      Enum.reduce(walls, game, fn pos, acc ->
        %{acc | tiles: Map.put(acc.tiles, pos, {22, 0x0E})}
      end)

    final =
      Enum.reduce_while(1..20, game, fn _, acc ->
        next = Centipede.tick(acc, 1)
        if next.player.health < 100, do: {:halt, next}, else: {:cont, next}
      end)

    # Player took a hit.
    assert final.player.health == 90
    # Old head was removed; the chain dropped to just the segment.
    assert length(final.stats) == 2

    # The surviving stat is now a head element on the board.
    remaining = Enum.at(final.stats, 1)
    {elem, _color} = Map.fetch!(final.tiles, {remaining.x, remaining.y})
    assert elem == @head
    assert remaining.leader == -1
  end
end
