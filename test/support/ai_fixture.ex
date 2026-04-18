defmodule ZztEx.Test.AIFixture do
  @moduledoc """
  Builds small `Game` snapshots for AI unit tests.

  A fresh game is a 60x25 empty board with a player, a single monster,
  optional wall tiles, and default player inventory. Callers override
  just the bits that matter for the behavior they're exercising.
  """

  alias ZztEx.Zzt.{Board, Game, Stat}

  @normal_wall 22
  @breakable 23
  @water 19

  @doc """
  Build a `%Game{}` for AI tests. Options:

    * `:player_xy`  — `{x, y}` for stat 0
    * `:monster`    — `%Stat{}` to place as stat 1 (with an :element opt)
    * `:element`    — element id to place at the monster's tile
    * `:color`      — tile color for the monster (default `0x0C`)
    * `:walls`      — list of `{x, y}` tiles set to Normal wall
    * `:breakables` — list of `{x, y}` tiles set to Breakable wall
    * `:water`      — list of `{x, y}` tiles set to Water
    * `:energizer`  — player energizer_ticks (default 0)
  """
  def game_with(opts) do
    {px, py} = Keyword.fetch!(opts, :player_xy)
    monster = Keyword.fetch!(opts, :monster)
    element = Keyword.fetch!(opts, :element)
    color = Keyword.get(opts, :color, 0x0C)
    walls = Keyword.get(opts, :walls, [])
    breakables = Keyword.get(opts, :breakables, [])
    water = Keyword.get(opts, :water, [])
    energizer = Keyword.get(opts, :energizer, 0)

    empty =
      for y <- 1..Board.height(), x <- 1..Board.width(), into: %{} do
        {{x, y}, {0, 0x0F}}
      end

    tiles =
      empty
      |> put_all(walls, {@normal_wall, 0x0E})
      |> put_all(breakables, {@breakable, 0x0E})
      |> put_all(water, {@water, 0x9F})
      |> Map.put({px, py}, {4, 0x1F})
      |> Map.put({monster.x, monster.y}, {element, color})

    stats = [
      %Stat{x: px, y: py, cycle: 1},
      monster
    ]

    %Game{
      tiles: tiles,
      stats: stats,
      player: %{
        health: 100,
        ammo: 0,
        gems: 0,
        keys: List.duplicate(false, 7),
        torches: 0,
        score: 0,
        energizer_ticks: energizer
      },
      stat_tick: 0
    }
  end

  @doc "Run `tick_fun` on the game up to `max` times or until `done?/1` is true."
  def tick_until(game, tick_fun, done?, max \\ 200) do
    Enum.reduce_while(1..max, game, fn _, acc ->
      if done?.(acc), do: {:halt, acc}, else: {:cont, tick_fun.(acc)}
    end)
  end

  defp put_all(tiles, positions, tile) do
    Enum.reduce(positions, tiles, fn pos, acc -> Map.put(acc, pos, tile) end)
  end
end
