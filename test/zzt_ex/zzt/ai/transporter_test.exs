defmodule ZztEx.Zzt.AI.TransporterTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Board, Game, Stat}

  @transporter 30
  @wall 22
  @boulder 24

  defp blank_tiles do
    for y <- 1..Board.height(), x <- 1..Board.width(), into: %{} do
      {{x, y}, {0, 0x0F}}
    end
  end

  defp base_player do
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

  # Player at (px, py). Transporters and extra tiles provided in opts.
  defp with_scene(player_xy, transporters, extras \\ []) do
    {px, py} = player_xy

    transporter_stats =
      for {{tx, ty}, {dx, dy}} <- transporters,
          do: %Stat{x: tx, y: ty, step_x: dx, step_y: dy, cycle: 2}

    tiles =
      transporters
      |> Enum.reduce(blank_tiles(), fn {{tx, ty}, _step}, acc ->
        Map.put(acc, {tx, ty}, {@transporter, 0x0F})
      end)
      |> then(fn t ->
        Enum.reduce(extras, t, fn {pos, tile}, acc -> Map.put(acc, pos, tile) end)
      end)
      |> Map.put({px, py}, {4, 0x1F})

    %Game{
      tiles: tiles,
      stats: [%Stat{x: px, y: py, cycle: 1}] ++ transporter_stats,
      player: base_player(),
      stat_tick: 0
    }
  end

  test "lone east-facing transporter kicks the player one square east" do
    # Player (10, 10) pushes into transporter (11, 10) facing east.
    game = with_scene({10, 10}, [{{11, 10}, {1, 0}}])

    final = Game.move_player(game, 1, 0)

    player = Enum.at(final.stats, 0)
    # Player ends up east of the transporter, on the vacated tile.
    assert {player.x, player.y} == {12, 10}
    # Transporter tile itself is untouched.
    assert Map.fetch!(final.tiles, {11, 10}) |> elem(0) == @transporter
    # The tile the player left is empty.
    assert Map.fetch!(final.tiles, {10, 10}) |> elem(0) == 0
  end

  test "transporter whose direction doesn't match the push is inert" do
    # Transporter faces north; player pushes east.
    game = with_scene({10, 10}, [{{11, 10}, {0, -1}}])

    final = Game.move_player(game, 1, 0)

    player = Enum.at(final.stats, 0)
    # Player doesn't move — transporter blocks.
    assert {player.x, player.y} == {10, 10}
  end

  test "paired transporters teleport the player through walls" do
    # Player at (10, 10). East-facing transporter at (11, 10). Walls at
    # (12, 10)..(14, 10). West-facing transporter at (15, 10). Empty at
    # (16, 10) — landing spot.
    extras =
      Enum.map(12..14, fn x -> {{x, 10}, {@wall, 0x0E}} end)

    game =
      with_scene({10, 10}, [{{11, 10}, {1, 0}}, {{15, 10}, {-1, 0}}], extras)

    final = Game.move_player(game, 1, 0)

    player = Enum.at(final.stats, 0)
    assert {player.x, player.y} == {16, 10}
  end

  test "no valid landing spot leaves the player put" do
    # East-facing transporter with a wall immediately east and no
    # reverse transporter — nowhere to teleport to.
    extras = [{{12, 10}, {@wall, 0x0E}}]

    game = with_scene({10, 10}, [{{11, 10}, {1, 0}}], extras)

    final = Game.move_player(game, 1, 0)

    player = Enum.at(final.stats, 0)
    assert {player.x, player.y} == {10, 10}
  end

  test "transporter shoves a boulder aside and lands the player on the vacated tile" do
    # East-facing transporter at (11, 10). Boulder at (12, 10) with empty (13, 10).
    extras = [{{12, 10}, {@boulder, 0x0F}}]

    game = with_scene({10, 10}, [{{11, 10}, {1, 0}}], extras)

    final = Game.move_player(game, 1, 0)

    # Boulder shoved east; player lands where the boulder was.
    assert Map.fetch!(final.tiles, {13, 10}) |> elem(0) == @boulder
    player = Enum.at(final.stats, 0)
    assert {player.x, player.y} == {12, 10}
  end
end
