defmodule ZztEx.Zzt.AI.LionTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.{Board, Game, Stat}
  alias ZztEx.Zzt.AI.Lion

  @lion 41
  @normal_wall 22

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

  # Build a game whose board is mostly empty (element 0), with an optional
  # set of `{x, y, element, color}` tile overrides, a player at `player_xy`,
  # and a lion at `lion_xy`.
  defp game_with(opts) do
    player_xy = Keyword.fetch!(opts, :player_xy)
    lion_xy = Keyword.fetch!(opts, :lion_xy)
    p1 = Keyword.get(opts, :p1, 0)
    energizer = Keyword.get(opts, :energizer, 0)
    walls = Keyword.get(opts, :walls, [])

    empty_tiles =
      for y <- 1..Board.height(), x <- 1..Board.width(), into: %{} do
        {{x, y}, {0, 0x0F}}
      end

    tiles =
      walls
      |> Enum.reduce(empty_tiles, fn {x, y}, acc -> Map.put(acc, {x, y}, {@normal_wall, 0x0E}) end)
      |> Map.put(player_xy, {4, 0x1F})
      |> Map.put(lion_xy, {@lion, 0x0C})

    {px, py} = player_xy
    {lx, ly} = lion_xy

    stats = [
      %Stat{x: px, y: py, cycle: 1},
      %Stat{x: lx, y: ly, cycle: 3, p1: p1, under_element: 0, under_color: 0x0F}
    ]

    %Game{
      tiles: tiles,
      stats: stats,
      player: base_player_state(%{energizer_ticks: energizer}),
      stat_tick: 0
    }
  end

  defp tick_until_change(game, acc_fun, max \\ 200) do
    # Roll the tick forward until `acc_fun.(game) != acc_fun.(initial)` or
    # until we hit `max` attempts — lion direction is random-ish, so we
    # need a bounded retry loop for any single-frame assertion.
    initial = acc_fun.(game)

    Enum.reduce_while(1..max, game, fn _, acc ->
      next = Lion.tick(acc, 1)
      if acc_fun.(next) != initial, do: {:halt, next}, else: {:cont, next}
    end)
  end

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  test "lion adjacent to player damages them and dies on contact" do
    # Player at (5, 5). Lion directly west at (4, 5). Walls on the lion's
    # other three sides so the only non-blocked action is stepping east
    # into the player.
    game =
      game_with(
        player_xy: {5, 5},
        lion_xy: {4, 5},
        walls: [{3, 5}, {4, 4}, {4, 6}]
      )

    final = tick_until_change(game, &{&1.player.health, length(&1.stats)})

    assert final.player.health == 90
    # Stats list is just the player now.
    assert length(final.stats) == 1
    # And the lion's cell is restored to whatever was underneath.
    {element, _color} = Map.fetch!(final.tiles, {4, 5})
    assert element == 0
  end

  test "energized player is unharmed; lion dies on contact" do
    game =
      game_with(
        player_xy: {5, 5},
        lion_xy: {4, 5},
        walls: [{3, 5}, {4, 4}, {4, 6}],
        energizer: 100
      )

    final = tick_until_change(game, &length(&1.stats))

    assert final.player.health == 100
    assert length(final.stats) == 1
  end

  test "lion boxed in by walls never moves" do
    game =
      game_with(
        player_xy: {20, 20},
        lion_xy: {5, 5},
        walls: [{4, 5}, {6, 5}, {5, 4}, {5, 6}]
      )

    final = Enum.reduce(1..50, game, fn _, acc -> Lion.tick(acc, 1) end)
    lion = Enum.at(final.stats, 1)

    assert {lion.x, lion.y} == {5, 5}
    assert length(final.stats) == 2
  end

  test "seeking lion (p1=9) closes the gap on an open board" do
    # Put the lion eight tiles east of the player on an empty board so it
    # has to march west through open space to reach them.
    game = game_with(player_xy: {5, 5}, lion_xy: {13, 5}, p1: 9)

    final =
      Enum.reduce(1..40, game, fn _, acc ->
        if length(acc.stats) > 1, do: Lion.tick(acc, 1), else: acc
      end)

    # Either the lion marched west toward the player or it collided and
    # died — both count as "closed the gap" for ZZT's seek behavior.
    case Enum.at(final.stats, 1) do
      nil -> :ok
      lion -> assert lion.x < 13
    end
  end
end
