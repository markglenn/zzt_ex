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

  alias ZztEx.Zzt.{AI, Board, Element, Oop, Stat, World}

  defstruct world: nil,
            board_index: 0,
            board: nil,
            tiles: %{},
            stats: [],
            player: %{},
            stat_tick: 0,
            pending_scroll: nil,
            flags: MapSet.new()

  @type player_state :: %{
          health: integer(),
          ammo: integer(),
          gems: integer(),
          keys: [boolean()],
          torches: integer(),
          score: integer(),
          energizer_ticks: non_neg_integer()
        }

  @type scroll :: %{title: String.t(), lines: [String.t()], line_pos: pos_integer()}

  @type t :: %__MODULE__{
          world: World.t(),
          board_index: non_neg_integer(),
          board: Board.t(),
          tiles: %{{1..60, 1..25} => {0..255, 0..255}},
          stats: [Stat.t()],
          player: player_state(),
          stat_tick: non_neg_integer(),
          pending_scroll: scroll() | nil,
          flags: MapSet.t()
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
      stat_tick: 0,
      flags: world.flags |> Enum.reject(&(&1 == "")) |> Enum.map(&String.upcase/1) |> MapSet.new()
    }
  end

  @doc "Whether the named world flag is currently set (case-insensitive)."
  @spec flag?(t(), String.t()) :: boolean()
  def flag?(%__MODULE__{flags: flags}, name) do
    MapSet.member?(flags, String.upcase(name))
  end

  @doc "Set a world flag (case-insensitive, capped at 10 flags like the reference)."
  @spec set_flag(t(), String.t()) :: t()
  def set_flag(%__MODULE__{flags: flags} = game, name) do
    upper = String.upcase(name)

    if MapSet.member?(flags, upper) or MapSet.size(flags) >= 10 do
      game
    else
      %{game | flags: MapSet.put(flags, upper)}
    end
  end

  @doc "Clear a world flag (case-insensitive)."
  @spec clear_flag(t(), String.t()) :: t()
  def clear_flag(%__MODULE__{flags: flags} = game, name) do
    %{game | flags: MapSet.delete(flags, String.upcase(name))}
  end

  @doc """
  Advance one stat pass: increment `stat_tick`, decrement the energizer
  timer, then tick every eligible stat. A pending scroll modal pauses
  the world until `dismiss_scroll/1` clears it.
  """
  @spec advance(t()) :: t()
  def advance(%__MODULE__{pending_scroll: scroll} = game) when not is_nil(scroll), do: game

  def advance(%__MODULE__{} = game) do
    %{game | stat_tick: game.stat_tick + 1}
    |> decrement_energizer()
    |> tick_stats()
  end

  @doc "Clear any pending scroll — lets the world tick again."
  @spec dismiss_scroll(t()) :: t()
  def dismiss_scroll(%__MODULE__{} = game), do: %{game | pending_scroll: nil}

  @doc """
  Move the scroll's cursor up (`-1`) or down (`+1`), clamping to the
  scroll's line count so the player can't scroll past either end.
  """
  @spec scroll_cursor(t(), integer()) :: t()
  def scroll_cursor(%__MODULE__{pending_scroll: nil} = game, _delta), do: game

  def scroll_cursor(%__MODULE__{pending_scroll: scroll} = game, delta) do
    count = length(scroll.lines)
    new_pos = scroll.line_pos + delta
    new_pos = new_pos |> max(1) |> min(max(count, 1))
    %{game | pending_scroll: %{scroll | line_pos: new_pos}}
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

  @doc """
  Move a tile (and its stat, if any) from `{from_x, from_y}` to
  `{to_x, to_y}`. Mirrors ZZT's `ElementMove`: if a stat lives at the
  source, delegate to `move_stat/4`; otherwise copy the tile directly
  and clear the source. Target's prior content is overwritten.
  """
  @spec element_move(t(), 1..60, 1..25, 1..60, 1..25) :: t()
  def element_move(%__MODULE__{} = game, from_x, from_y, to_x, to_y) do
    case find_stat_at(game.stats, from_x, from_y) do
      nil ->
        src_tile = Map.fetch!(game.tiles, {from_x, from_y})

        tiles =
          game.tiles
          |> Map.put({to_x, to_y}, src_tile)
          |> Map.put({from_x, from_y}, {0, 0})

        %{game | tiles: tiles}

      idx ->
        move_stat(game, idx, to_x, to_y)
    end
  end

  @doc """
  Attempt to push the tile at `{x, y}` one step along `{dx, dy}`. Ports
  `ElementPushablePush`:

    * Sliders only move along their own axis; everything else uses the
      static Pushable flag.
    * If the push destination is occupied, try pushing that tile first
      (recursively).
    * If the destination ends up occupied by a destructible non-walkable
      tile (other than the player), crush it.
    * If the destination is walkable afterward, the pushed tile slides in.
  """
  @spec push_tile(t(), integer(), integer(), integer(), integer()) :: t()
  def push_tile(%__MODULE__{} = game, _x, _y, 0, 0), do: game

  def push_tile(%__MODULE__{} = game, x, y, dx, dy) do
    case Map.get(game.tiles, {x, y}) do
      nil ->
        game

      {element, _} ->
        if Element.pushable?(element, dx, dy) do
          do_push(game, x, y, dx, dy)
        else
          game
        end
    end
  end

  defp do_push(game, x, y, dx, dy) do
    tx = x + dx
    ty = y + dy

    if in_bounds?(tx, ty) do
      {target_elem, _} = Map.fetch!(game.tiles, {tx, ty})

      game =
        if target_elem != 0 do
          push_tile(game, tx, ty, dx, dy)
        else
          game
        end

      # Re-read target after recursion.
      {target_elem, _} = Map.fetch!(game.tiles, {tx, ty})

      game =
        if not Element.walkable?(target_elem) and
             Element.destructible?(target_elem) and target_elem != 4 do
          damage_tile(game, tx, ty)
        else
          game
        end

      {target_elem, _} = Map.fetch!(game.tiles, {tx, ty})

      if Element.walkable?(target_elem) do
        element_move(game, x, y, tx, ty)
      else
        game
      end
    else
      game
    end
  end

  @doc """
  Damage whatever is at `{x, y}`. Mirrors `BoardDamageTile`: if there's
  a stat there, `DamageStat` semantics (player takes 10, monster dies);
  otherwise the tile is set to empty.
  """
  @spec damage_tile(t(), 1..60, 1..25) :: t()
  def damage_tile(%__MODULE__{} = game, x, y) do
    case find_stat_at(game.stats, x, y) do
      nil -> %{game | tiles: Map.put(game.tiles, {x, y}, {0, 0x0F})}
      0 -> damage_player(game, 10)
      idx -> remove_stat(game, idx)
    end
  end

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s -> s.x == x and s.y == y end)
  end

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
      true -> change_board(game, exit_board, entry_x, entry_y, dx, dy)
    end
  end

  @doc """
  Transition to another board, preserving the player's inventory and
  placing them at `{entry_x, entry_y}` on the new board. The entry
  tile's TouchProc fires (so pickups / monster fights / doors at the
  seam behave as expected). If the tile still isn't walkable after
  that, the transition reverts and the previous board state stays.
  """
  @spec change_board(t(), non_neg_integer(), 1..60, 1..25, integer(), integer()) :: t()
  def change_board(
        %__MODULE__{world: world, player: player} = game,
        new_idx,
        entry_x,
        entry_y,
        dx \\ 0,
        dy \\ 0
      ) do
    fresh = new(world, new_idx)
    fresh = %{fresh | player: player}

    {entry_elem, _color} = Map.fetch!(fresh.tiles, {entry_x, entry_y})

    fresh =
      if entry_elem == 4 do
        fresh
      else
        {fresh, _dx, _dy} = ZztEx.Zzt.Touch.touch(fresh, entry_x, entry_y, 0, dx, dy)
        fresh
      end

    {entry_elem, _color} = Map.fetch!(fresh.tiles, {entry_x, entry_y})

    cond do
      entry_elem == 4 -> fresh
      Element.walkable?(entry_elem) -> move_stat(fresh, 0, entry_x, entry_y)
      true -> game
    end
  end

  @doc """
  Fire a bullet (or star) from `{x, y}` in direction `{dx, dy}`. Ports
  `BoardShoot`: if the tile immediately in that direction is walkable or
  water, a new bullet stat is spawned there. If it's a breakable (or a
  source-appropriate destructible), the tile is damaged in place without
  spawning a bullet. Otherwise the shot fails and the caller sees `false`.

    * `element` — usually `18` (Bullet); `15` for a Star shot.
    * `source` — `0` for the player, non-zero for an enemy. The bullet's
      `p1` carries this through subsequent bullet ticks for friendly-fire
      rules.
  """
  @spec board_shoot(t(), 1..60, 1..25, integer(), integer(), 0..255, 0..255) ::
          {t(), boolean()}
  def board_shoot(%__MODULE__{} = game, x, y, dx, dy, source, element \\ 18) do
    tx = x + dx
    ty = y + dy

    case Map.get(game.tiles, {tx, ty}) do
      nil ->
        {game, false}

      {target_elem, _color} ->
        cond do
          Element.walkable?(target_elem) or target_elem == 19 ->
            template = %Stat{
              x: 0,
              y: 0,
              cycle: 1,
              step_x: dx,
              step_y: dy,
              p1: source,
              p2: 100
            }

            game = add_stat(game, tx, ty, element, 0x0F, template)
            {game, true}

          target_elem == 23 or shootable?(target_elem, source) ->
            {damage_tile(game, tx, ty), true}

          true ->
            {game, false}
        end
    end
  end

  # `BoardShoot`'s destructible clause: damage only when the target is
  # aligned with the source — player bullets leave the player alone,
  # enemy bullets only hit the player (breakables are handled above).
  defp shootable?(element, source) do
    Element.destructible?(element) and element == 4 == (source != 0)
  end

  @doc """
  Teleport through a passage at `{x, y}`. Ports `BoardPassageTeleport`:
  take the passage's color and its stat's `p3` (target board), switch
  to that board, scan for a passage of the matching color, and move
  the player there.
  """
  @spec passage_teleport(t(), 1..60, 1..25) :: t()
  def passage_teleport(%__MODULE__{world: world, player: player} = game, x, y) do
    {_, color} = Map.fetch!(game.tiles, {x, y})

    with idx when is_integer(idx) <- find_stat_at(game.stats, x, y),
         stat <- Enum.at(game.stats, idx),
         target_idx when target_idx > 0 and target_idx < length(world.boards) <- stat.p3 do
      fresh = new(world, target_idx)
      fresh = %{fresh | player: player}

      case find_colored_passage(fresh, color) do
        {nx, ny} -> move_stat(fresh, 0, nx, ny)
        nil -> fresh
      end
    else
      _ -> game
    end
  end

  defp find_colored_passage(%__MODULE__{tiles: tiles}, color) do
    tiles
    |> Enum.find_value(fn
      {{x, y}, {11, ^color}} -> {x, y}
      _ -> nil
    end)
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
      :tiger -> AI.Tiger.tick(game, cur_idx)
      :bullet -> AI.Bullet.tick(game, cur_idx)
      :star -> AI.Star.tick(game, cur_idx)
      :spinning_gun -> AI.SpinningGun.tick(game, cur_idx)
      :bear -> AI.Bear.tick(game, cur_idx)
      :ruffian -> AI.Ruffian.tick(game, cur_idx)
      :slime -> AI.Slime.tick(game, cur_idx)
      :shark -> AI.Shark.tick(game, cur_idx)
      :pusher -> AI.Pusher.tick(game, cur_idx)
      :head -> AI.Centipede.tick(game, cur_idx)
      :segment -> AI.Centipede.segment_tick(game, cur_idx)
      :conveyor_cw -> AI.Conveyor.cw_tick(game, cur_idx)
      :conveyor_ccw -> AI.Conveyor.ccw_tick(game, cur_idx)
      :object -> Oop.tick(game, cur_idx)
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
