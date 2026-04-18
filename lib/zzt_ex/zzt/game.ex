defmodule ZztEx.Zzt.Game do
  @moduledoc """
  Mutable runtime state for a ZZT world in play.

  Loading a `.zzt` file gives us a static `World` (header + boards). Playing
  it means advancing stats every cycle, moving tiles, attacking, picking
  things up, and bookkeeping the player inventory. That mutable snapshot
  lives here.

  The model:

    * `tiles` — the current board as a `%{{x, y} => {element, color}}` map
    * `stats` — list of active entities; index 0 is always the player
    * `player` — inventory/vitals (health, ammo, gems, keys, etc.)
    * `stat_tick` — monotonic counter advanced once per `advance/1`

  `advance/1` is one "stat pass" in ZZT terms. Every tick we walk the stats
  in index order; any stat whose cycle divides `stat_tick` runs its tick
  handler (currently only Lion).
  """

  alias ZztEx.Zzt.{AI, Board, Element, Stat, World}

  defstruct world: nil,
            board_index: 0,
            board: nil,
            tiles: %{},
            stats: [],
            player: %{},
            stat_tick: 0

  @type player_state :: %{
          health: integer(),
          ammo: integer(),
          gems: integer(),
          keys: [boolean()],
          torches: integer(),
          score: integer(),
          energizer_ticks: non_neg_integer()
        }

  @type t :: %__MODULE__{
          world: World.t(),
          board_index: non_neg_integer(),
          board: Board.t(),
          tiles: %{{1..60, 1..25} => {0..255, 0..255}},
          stats: [Stat.t()],
          player: player_state(),
          stat_tick: non_neg_integer()
        }

  @doc """
  Build a fresh game from a world, starting on `:current_board` by default.
  """
  @spec new(World.t(), non_neg_integer() | nil) :: t()
  def new(%World{} = world, board_index \\ nil) do
    idx = board_index || world.current_board
    board = Enum.at(world.boards, idx)

    %__MODULE__{
      world: world,
      board_index: idx,
      board: board,
      tiles: tiles_from_list(board.tiles),
      stats: board.stats,
      player: %{
        health: world.health,
        ammo: world.ammo,
        gems: world.gems,
        keys: world.keys,
        torches: world.torches,
        score: world.score,
        energizer_ticks: world.energizer_cycles
      },
      stat_tick: 0
    }
  end

  @doc """
  Advance one stat pass: increment `stat_tick`, decrement the energizer
  timer, then tick every eligible stat.
  """
  @spec advance(t()) :: t()
  def advance(%__MODULE__{} = game) do
    %{game | stat_tick: game.stat_tick + 1}
    |> decrement_energizer()
    |> tick_stats()
  end

  @doc """
  Re-materialize a `%Board{}` from the current game state so the renderer
  (which takes a plain Board) can draw the live tiles without knowing
  about `Game`.
  """
  @spec to_board(t()) :: Board.t()
  def to_board(%__MODULE__{board: board} = game) do
    %Board{board | tiles: tiles_to_list(game.tiles), stats: game.stats}
  end

  @doc "Tile at `{x, y}`, or `nil` if off-board."
  @spec tile_at(t(), integer(), integer()) :: {0..255, 0..255} | nil
  def tile_at(%__MODULE__{tiles: tiles}, x, y), do: Map.get(tiles, {x, y})

  @doc """
  Move the stat at `stat_idx` to `{nx, ny}`. Restores the stat's
  `under` tile at the old position and caches whatever was at the target
  as the stat's new under. Assumes the caller already verified the target
  is walkable.
  """
  @spec move_stat(t(), non_neg_integer(), 1..60, 1..25) :: t()
  def move_stat(%__MODULE__{} = game, stat_idx, nx, ny) do
    stat = Enum.at(game.stats, stat_idx)
    target_tile = Map.fetch!(game.tiles, {nx, ny})
    mover_tile = Map.fetch!(game.tiles, {stat.x, stat.y})

    new_tiles =
      game.tiles
      |> Map.put({stat.x, stat.y}, {stat.under_element, stat.under_color})
      |> Map.put({nx, ny}, mover_tile)

    new_stat = %{
      stat
      | x: nx,
        y: ny,
        under_element: elem(target_tile, 0),
        under_color: elem(target_tile, 1)
    }

    %{game | tiles: new_tiles, stats: List.replace_at(game.stats, stat_idx, new_stat)}
  end

  @doc """
  Add a new stat to the board, placing its element at `{x, y}` and
  saving whatever was there as the new stat's under-tile. Mirrors
  ZZT's `AddStat` — used by Slime to spawn copies and (eventually) by
  `BoardShoot` to spawn bullets.
  """
  @spec add_stat(t(), 1..60, 1..25, 0..255, 0..255, Stat.t()) :: t()
  def add_stat(%__MODULE__{} = game, x, y, element, color, template \\ %Stat{x: 0, y: 0}) do
    under = Map.get(game.tiles, {x, y}, {0, 0})

    new_stat = %Stat{
      template
      | x: x,
        y: y,
        under_element: elem(under, 0),
        under_color: elem(under, 1)
    }

    %{
      game
      | tiles: Map.put(game.tiles, {x, y}, {element, color}),
        stats: game.stats ++ [new_stat]
    }
  end

  @doc """
  Remove the stat at `stat_idx` and restore whatever was beneath it. All
  remaining stats have their `follower`/`leader` references rewritten so
  pointers to the removed stat become `-1` and pointers to higher indices
  shift down by one. Callers mid-tick still need to re-acquire their own
  iteration index.
  """
  @spec remove_stat(t(), non_neg_integer()) :: t()
  def remove_stat(%__MODULE__{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    new_tiles = Map.put(game.tiles, {stat.x, stat.y}, {stat.under_element, stat.under_color})

    new_stats =
      game.stats
      |> List.delete_at(stat_idx)
      |> Enum.map(fn s ->
        %Stat{
          s
          | leader: shift_ref(s.leader, stat_idx),
            follower: shift_ref(s.follower, stat_idx)
        }
      end)

    %{game | tiles: new_tiles, stats: new_stats}
  end

  defp shift_ref(-1, _removed), do: -1
  defp shift_ref(ref, removed) when ref < removed, do: ref
  defp shift_ref(ref, removed) when ref == removed, do: -1
  defp shift_ref(ref, _removed), do: ref - 1

  @doc "Apply `amount` damage to the player (clamped to zero)."
  @spec damage_player(t(), non_neg_integer()) :: t()
  def damage_player(%__MODULE__{} = game, amount) do
    %{game | player: %{game.player | health: max(0, game.player.health - amount)}}
  end

  @doc "Whether the player currently has an active energizer."
  @spec energized?(t()) :: boolean()
  def energized?(%__MODULE__{player: %{energizer_ticks: n}}), do: n > 0

  @doc """
  A monster steps onto the player. Default behavior for contact monsters:
  deal 10 damage and die on contact; when the player is energized the
  monster dies without damaging.
  """
  @spec collide_with_player(t(), non_neg_integer(), non_neg_integer()) :: t()
  def collide_with_player(%__MODULE__{} = game, attacker_idx, damage \\ 10) do
    if energized?(game) do
      remove_stat(game, attacker_idx)
    else
      game
      |> damage_player(damage)
      |> remove_stat(attacker_idx)
    end
  end

  @doc """
  Move the player in response to input. `{dx, dy}` is one cardinal step.

  Flow matches `ElementPlayerTick`: fire the target tile's `TouchProc`
  first (which may pick things up, chop forests, damage monsters,
  consume a key, reveal invisible walls, or block the mover by zeroing
  the delta), then — if the delta is still non-zero and the target is
  walkable afterwards — slide the player onto it.

  Walking off the edge triggers a board transition when the current
  board has a neighbor wired up in that direction.
  """
  @spec move_player(t(), integer(), integer()) :: t()
  def move_player(%__MODULE__{} = game, dx, dy) do
    cond do
      game.player.health <= 0 ->
        game

      true ->
        player = Enum.at(game.stats, 0)
        tx = player.x + dx
        ty = player.y + dy

        cond do
          not in_bounds?(tx, ty) -> board_edge_touch(game, dx, dy)
          true -> touch_and_move(game, tx, ty, dx, dy)
        end
    end
  end

  defp touch_and_move(game, tx, ty, dx, dy) do
    {game, dx, dy} = ZztEx.Zzt.Touch.touch(game, tx, ty, 0, dx, dy)
    finalize_move(game, dx, dy)
  end

  # ZZT's BoardEdgeTouch: the "tile" the player just stepped onto is the
  # virtual border around the playfield. Pick the matching neighbor
  # board from Board.Info.NeighborBoards[N,S,W,E]; if it's non-zero,
  # switch boards and place the player on the opposite edge.
  # Without a loaded board or world there's no neighbor wiring; the edge
  # just blocks, mirroring a board that has every exit set to 0.
  defp board_edge_touch(%__MODULE__{board: nil} = game, _dx, _dy), do: game
  defp board_edge_touch(%__MODULE__{world: nil} = game, _dx, _dy), do: game

  defp board_edge_touch(%__MODULE__{board: board, world: world} = game, dx, dy) do
    player = Enum.at(game.stats, 0)

    {exit_board, entry_x, entry_y} =
      cond do
        dy == -1 -> {board.exit_north, player.x, Board.height()}
        dy == 1 -> {board.exit_south, player.x, 1}
        dx == -1 -> {board.exit_west, Board.width(), player.y}
        dx == 1 -> {board.exit_east, 1, player.y}
      end

    cond do
      exit_board == 0 -> game
      exit_board >= length(world.boards) -> game
      true -> change_board(game, exit_board, entry_x, entry_y)
    end
  end

  @doc """
  Transition to another board, preserving the player's inventory and
  placing them at `{entry_x, entry_y}` on the new board. If the entry
  tile isn't walkable the move is aborted and the current board state
  is kept (matches ZZT's "revert" path in `ElementBoardEdgeTouch`).
  """
  @spec change_board(t(), non_neg_integer(), 1..60, 1..25) :: t()
  def change_board(%__MODULE__{world: world, player: player} = game, new_idx, entry_x, entry_y) do
    fresh = new(world, new_idx)
    fresh = %{fresh | player: player}

    {entry_elem, _color} = Map.fetch!(fresh.tiles, {entry_x, entry_y})

    cond do
      entry_elem == 4 ->
        # Player already sits on the entry tile; nothing to do.
        fresh

      Element.walkable?(entry_elem) ->
        # Move the player stat onto the entry tile.
        move_stat(fresh, 0, entry_x, entry_y)

      true ->
        # Entry blocked — stay on the current board.
        game
    end
  end

  defp finalize_move(game, 0, 0), do: game

  defp finalize_move(game, dx, dy) do
    player = Enum.at(game.stats, 0)
    tx = player.x + dx
    ty = player.y + dy

    if in_bounds?(tx, ty) and walkable?(game, tx, ty) do
      move_stat(game, 0, tx, ty)
    else
      game
    end
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp walkable?(game, x, y) do
    case Map.get(game.tiles, {x, y}) do
      {element, _color} -> Element.walkable?(element)
      nil -> false
    end
  end

  # ---- internals --------------------------------------------------------

  defp decrement_energizer(%{player: %{energizer_ticks: n} = p} = game) when n > 0 do
    %{game | player: %{p | energizer_ticks: n - 1}}
  end

  defp decrement_energizer(game), do: game

  # ZZT ticks stat i when (stat_tick mod cycle) == (i mod cycle). That
  # staggers stats sharing a cycle so they don't all burst on the same
  # frame, giving the classic "scattered" monster pacing.
  defp tick_stats(game) do
    # Snapshot the pre-tick monster positions; a stat's position is how we
    # re-locate it in the (possibly shifted) post-tick list each iteration.
    positions =
      game.stats
      |> Enum.with_index()
      |> Enum.drop(1)
      |> Enum.map(fn {stat, idx} -> {idx, stat.x, stat.y} end)

    Enum.reduce(positions, game, fn {orig_idx, ox, oy}, acc ->
      case find_stat_at(acc.stats, ox, oy) do
        nil -> acc
        cur_idx -> maybe_tick_stat(acc, cur_idx, orig_idx)
      end
    end)
  end

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s -> s.x == x and s.y == y end)
  end

  defp maybe_tick_stat(game, cur_idx, orig_idx) do
    stat = Enum.at(game.stats, cur_idx)

    if should_tick?(stat, orig_idx, game.stat_tick) do
      dispatch_tick(game, cur_idx, stat)
    else
      game
    end
  end

  defp should_tick?(%Stat{cycle: 0}, _idx, _tick), do: false

  defp should_tick?(%Stat{cycle: cycle}, stat_idx, stat_tick) do
    rem(stat_tick, cycle) == rem(stat_idx, cycle)
  end

  defp dispatch_tick(game, cur_idx, stat) do
    {element, _color} = Map.get(game.tiles, {stat.x, stat.y}, {0, 0})

    case Element.name(element) do
      :lion -> AI.Lion.tick(game, cur_idx)
      :bear -> AI.Bear.tick(game, cur_idx)
      :ruffian -> AI.Ruffian.tick(game, cur_idx)
      :slime -> AI.Slime.tick(game, cur_idx)
      :shark -> AI.Shark.tick(game, cur_idx)
      :pusher -> AI.Pusher.tick(game, cur_idx)
      :head -> AI.Centipede.tick(game, cur_idx)
      :segment -> AI.Centipede.segment_tick(game, cur_idx)
      _ -> game
    end
  end

  defp tiles_from_list(list) do
    for {tile, idx} <- Enum.with_index(list), into: %{} do
      {{rem(idx, Board.width()) + 1, div(idx, Board.width()) + 1}, tile}
    end
  end

  defp tiles_to_list(tiles_map) do
    for y <- 1..Board.height(), x <- 1..Board.width() do
      Map.get(tiles_map, {x, y}, {0, 0})
    end
  end
end
