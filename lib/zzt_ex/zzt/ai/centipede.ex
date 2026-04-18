defmodule ZztEx.Zzt.AI.Centipede do
  @moduledoc """
  Centipede head and segment behavior, ported from ZZT's
  `ElementCentipedeHeadTick`.

  A centipede is a chain of stats linked by `leader`/`follower` fields:

      head (leader = -1, follower = seg1)
        |
      seg1 (leader = head, follower = seg2)
        |
      seg2 (leader = seg1, follower = -1)

  Only the head ticks. Each tick the head:

    1. Picks up its stored `step`, rerolling to a random direction if it
       was `{0, 0}`.
    2. If aligned with the player on X or Y, redirects that axis toward
       the player with probability `p1 / 10`.
    3. Attempts to move. Blocked? Try rotating 90° (CW or CCW at random),
       then the opposite rotation, then reverse. If *every* direction is
       blocked, flip the chain — the tail becomes the new head and all
       leader/follower links invert.
    4. If the target tile is the player, attack: promote the follower to
       head (so the tail survives), then the old head dies.
    5. Otherwise move into the target and drag the chain along: each
       segment steps into the position its leader just vacated.

  Segments are passive; they don't tick themselves.
  """

  alias ZztEx.Zzt.{Element, Game, Stat}
  alias ZztEx.Zzt.AI.Directions

  @head 44
  @segment 45

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, head_idx) do
    head = Enum.at(game.stats, head_idx)
    {sx, sy} = pick_direction(head, Enum.at(game.stats, 0))

    game = set_step(game, head_idx, sx, sy)
    try_step(game, head_idx)
  end

  defp pick_direction(head, player) do
    {sx, sy} =
      if head.step_x == 0 and head.step_y == 0 do
        Directions.random_step()
      else
        {head.step_x, head.step_y}
      end

    # Axis-aligned seek, same rules as ZZT: if we share a column with
    # the player and roll under p1, flip the vertical step toward them.
    sy =
      if head.x == player.x and :rand.uniform(10) - 1 < head.p1 do
        Directions.signum(player.y - head.y)
      else
        sy
      end

    sx =
      if head.y == player.y and :rand.uniform(10) - 1 < head.p1 do
        Directions.signum(player.x - head.x)
      else
        sx
      end

    {sx, sy}
  end

  # Try the primary step; if blocked, try CW / CCW / 180° in turn. If
  # every candidate is blocked, the chain reverses in place.
  defp try_step(game, head_idx) do
    head = Enum.at(game.stats, head_idx)
    primary = {head.step_x, head.step_y}
    {first_rot, second_rot} = random_turn_order(primary)
    reverse = negate(primary)

    case find_open(game, head_idx, [primary, first_rot, second_rot, reverse]) do
      {sx, sy} ->
        game
        |> set_step(head_idx, sx, sy)
        |> apply_move(head_idx, sx, sy)

      nil ->
        reverse_chain(game, head_idx)
    end
  end

  defp apply_move(game, head_idx, sx, sy) do
    head = Enum.at(game.stats, head_idx)
    tx = head.x + sx
    ty = head.y + sy

    if player_at?(game, tx, ty) do
      attack_player(game, head_idx)
    else
      chain_shift(game, head_idx, tx, ty)
    end
  end

  # Walk each candidate in order and return the first that resolves to a
  # walkable tile (or the player, since hitting the player is a legal move).
  defp find_open(game, head_idx, candidates) do
    head = Enum.at(game.stats, head_idx)

    Enum.find(candidates, fn {dx, dy} ->
      step_open?(game, head.x + dx, head.y + dy)
    end)
  end

  defp step_open?(game, x, y) do
    cond do
      not in_bounds?(x, y) ->
        false

      player_at?(game, x, y) ->
        true

      true ->
        case Game.tile_at(game, x, y) do
          {elem, _} -> Element.walkable?(elem)
          nil -> false
        end
    end
  end

  # Head moves to {tx, ty}; each segment slides into whichever position
  # its leader just vacated. Moving head-first lets `Game.move_stat`
  # correctly capture and restore under-tiles all the way down the chain.
  defp chain_shift(game, head_idx, tx, ty) do
    chain = collect_chain(game, head_idx)

    old_positions =
      Enum.map(chain, fn idx ->
        stat = Enum.at(game.stats, idx)
        {stat.x, stat.y}
      end)

    new_positions = [{tx, ty} | Enum.drop(old_positions, -1)]

    chain
    |> Enum.zip(new_positions)
    |> Enum.reduce(game, fn {idx, {nx, ny}}, acc -> Game.move_stat(acc, idx, nx, ny) end)
  end

  defp collect_chain(game, idx, acc \\ []) do
    stat = Enum.at(game.stats, idx)
    acc = acc ++ [idx]

    if stat.follower >= 0 and stat.follower != idx do
      collect_chain(game, stat.follower, acc)
    else
      acc
    end
  end

  # All directions are blocked. Keep the chain exactly where it is but
  # swap the head and tail elements and invert every leader/follower
  # link so the formerly-trailing stat drives movement next tick.
  defp reverse_chain(game, head_idx) do
    chain = collect_chain(game, head_idx)

    case chain do
      [_only_head] ->
        game

      _ ->
        reversed = Enum.reverse(chain)
        old_head = Enum.at(game.stats, head_idx)
        old_tail = Enum.at(game.stats, List.last(chain))

        {_, old_head_color} = Map.fetch!(game.tiles, {old_head.x, old_head.y})
        {_, old_tail_color} = Map.fetch!(game.tiles, {old_tail.x, old_tail.y})

        tiles =
          game.tiles
          |> Map.put({old_head.x, old_head.y}, {@segment, old_head_color})
          |> Map.put({old_tail.x, old_tail.y}, {@head, old_tail_color})

        stats =
          reversed
          |> Enum.with_index()
          |> Enum.reduce(game.stats, fn {idx, pos}, acc ->
            leader = if pos == 0, do: -1, else: Enum.at(reversed, pos - 1)
            follower = Enum.at(reversed, pos + 1, -1)
            stat = Enum.at(acc, idx)
            List.replace_at(acc, idx, %Stat{stat | leader: leader, follower: follower})
          end)

        %{game | tiles: tiles, stats: stats}
    end
  end

  # Head steps onto the player. Promote the follower (if any) to head so
  # the chain doesn't strand, then apply standard contact damage to the
  # player and remove the old head.
  defp attack_player(game, head_idx) do
    head = Enum.at(game.stats, head_idx)

    game =
      if head.follower >= 0 do
        promote_to_head(game, head.follower)
      else
        game
      end

    Game.collide_with_player(game, head_idx)
  end

  defp promote_to_head(game, follower_idx) do
    follower = Enum.at(game.stats, follower_idx)
    {_elem, color} = Map.fetch!(game.tiles, {follower.x, follower.y})

    tiles = Map.put(game.tiles, {follower.x, follower.y}, {@head, color})
    stats = List.replace_at(game.stats, follower_idx, %Stat{follower | leader: -1})

    %{game | tiles: tiles, stats: stats}
  end

  defp set_step(game, head_idx, sx, sy) do
    stat = Enum.at(game.stats, head_idx)
    updated = %Stat{stat | step_x: sx, step_y: sy}
    %{game | stats: List.replace_at(game.stats, head_idx, updated)}
  end

  # Screen-space rotation: y grows downward, so CW is (x,y) → (-y, x).
  defp rotate_cw({x, y}), do: {-y, x}
  defp rotate_ccw({x, y}), do: {y, -x}
  defp negate({x, y}), do: {-x, -y}

  defp random_turn_order(step) do
    if :rand.uniform(2) == 1 do
      {rotate_cw(step), rotate_ccw(step)}
    else
      {rotate_ccw(step), rotate_cw(step)}
    end
  end

  defp player_at?(game, x, y) do
    case game.stats do
      [%{x: px, y: py} | _] -> x == px and y == py
      _ -> false
    end
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25
end
