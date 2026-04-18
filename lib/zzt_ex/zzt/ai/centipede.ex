defmodule ZztEx.Zzt.AI.Centipede do
  @moduledoc """
  Centipede head and segment behavior, ported one-to-one from
  `ElementCentipedeHeadTick` / `ElementCentipedeSegmentTick` in the
  reconstruction-of-zzt source release.

  Head tick (each stat pass the head is eligible):

    1. Redirect `step` with priority player-seek (axis-aligned, `p1/10`),
       random retarget (`p2`-weighted, also when step is `{0, 0}`), or
       keep the current step.
    2. Try to move: primary → random perpendicular → opposite
       perpendicular → reverse of primary. If all four are blocked, set
       `step = {0, 0}` as the "stuck" signal.
    3. If stuck, flip the chain in place (head becomes segment, tail
       becomes head, leader/follower pairs swap at each stat).
    4. Otherwise if the target tile holds the player, promote the follower
       to head (inheriting the head's step so the body keeps marching)
       and apply the standard contact attack.
    5. Otherwise move the head; then walk the chain, linking unclaimed
       segments directly behind or to the side of each stat's motion,
       inheriting p1/p2 and updating the step before the segment slides
       into its leader's vacated tile.

  Segment tick (orphan countdown):

    * If `leader == -1`, decrement (so next pass `leader = -2`).
    * If `leader < -1`, the segment has been orphaned long enough: its
      tile is promoted to a centipede head. From the next head tick it
      drives its own (possibly one-stat) chain.
  """

  alias ZztEx.Zzt.{Game, Stat}
  alias ZztEx.Zzt.AI.Directions

  @head 44
  @segment 45
  @player 4

  # ---- head --------------------------------------------------------------

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, head_idx) do
    game = seek_or_retarget(game, head_idx)
    game = try_directions(game, head_idx)

    head = Enum.at(game.stats, head_idx)

    cond do
      head.step_x == 0 and head.step_y == 0 ->
        reverse_chain(game, head_idx)

      player_at?(game, head.x + head.step_x, head.y + head.step_y) ->
        attack_player(game, head_idx)

      true ->
        move_and_propagate(game, head_idx)
    end
  end

  # Pascal: `if X = Player.X and Random(10) < P1 then StepY := Signum(...);
  # StepX := 0; else if Y = Player.Y ... else if (Random(10)*4 < P2) or step zero
  # then CalcDirectionRnd(StepX, StepY); end`.
  defp seek_or_retarget(game, head_idx) do
    head = Enum.at(game.stats, head_idx)
    player = Enum.at(game.stats, 0)

    {sx, sy} =
      cond do
        head.x == player.x and :rand.uniform(10) - 1 < head.p1 ->
          {0, Directions.signum(player.y - head.y)}

        head.y == player.y and :rand.uniform(10) - 1 < head.p1 ->
          {Directions.signum(player.x - head.x), 0}

        (:rand.uniform(10) - 1) * 4 < head.p2 or (head.step_x == 0 and head.step_y == 0) ->
          Directions.random_step()

        true ->
          {head.step_x, head.step_y}
      end

    set_step(game, head_idx, sx, sy)
  end

  # Pascal: primary → random perpendicular (`((Random(2)*2)-1)`-signed) →
  # opposite perpendicular → reverse of primary → else step:={0,0}.
  defp try_directions(game, head_idx) do
    head = Enum.at(game.stats, head_idx)
    primary = {head.step_x, head.step_y}
    {perp1, perp2} = random_perpendiculars(primary)
    reverse = negate(primary)

    chosen =
      Enum.find([primary, perp1, perp2, reverse], fn {dx, dy} ->
        step_open?(game, head.x + dx, head.y + dy)
      end)

    case chosen do
      {sx, sy} -> set_step(game, head_idx, sx, sy)
      nil -> set_step(game, head_idx, 0, 0)
    end
  end

  defp step_open?(game, x, y) do
    cond do
      not in_bounds?(x, y) ->
        false

      player_at?(game, x, y) ->
        true

      true ->
        case Game.tile_at(game, x, y) do
          {elem, _} -> ZztEx.Zzt.Element.walkable?(elem)
          nil -> false
        end
    end
  end

  # Head steps onto the player. Promote the follower with the head's step
  # (Pascal: `Follower.StepX := StepX; Follower.StepY := StepY;`) so the
  # chain keeps marching, then apply standard contact attack.
  defp attack_player(game, head_idx) do
    head = Enum.at(game.stats, head_idx)

    game =
      if head.follower > 0 do
        promote_follower(game, head.follower, head.step_x, head.step_y)
      else
        game
      end

    Game.collide_with_player(game, head_idx)
  end

  defp promote_follower(game, follower_idx, step_x, step_y) do
    follower = Enum.at(game.stats, follower_idx)
    {_, color} = Map.fetch!(game.tiles, {follower.x, follower.y})

    tiles = Map.put(game.tiles, {follower.x, follower.y}, {@head, color})

    stats =
      List.replace_at(
        game.stats,
        follower_idx,
        %Stat{follower | leader: -1, step_x: step_x, step_y: step_y}
      )

    %{game | tiles: tiles, stats: stats}
  end

  # Pascal:
  #   Board.Tiles[X][Y].Element := E_CENTIPEDE_SEGMENT;
  #   Leader := -1;
  #   while Board.Stats[statId].Follower > 0 do begin
  #     tmp := Board.Stats[statId].Follower;
  #     Board.Stats[statId].Follower := Board.Stats[statId].Leader;
  #     Board.Stats[statId].Leader := tmp;
  #     statId := tmp;
  #   end;
  #   Board.Stats[statId].Follower := Board.Stats[statId].Leader;
  #   Board.Tiles[Stats[statId].X][Stats[statId].Y].Element := E_CENTIPEDE_HEAD;
  defp reverse_chain(game, head_idx) do
    head = Enum.at(game.stats, head_idx)
    {_, head_color} = Map.fetch!(game.tiles, {head.x, head.y})

    game =
      game
      |> put_tile({head.x, head.y}, {@segment, head_color})
      |> update_stat(head_idx, fn s -> %Stat{s | leader: -1} end)

    {game, final_idx} = swap_walk(game, head_idx)

    final = Enum.at(game.stats, final_idx)

    game
    |> update_stat(final_idx, fn s -> %Stat{s | follower: final.leader} end)
    |> promote_tile_to_head(final.x, final.y)
  end

  defp swap_walk(game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)

    if stat.follower > 0 do
      tmp = stat.follower
      updated = %Stat{stat | follower: stat.leader, leader: tmp}
      game = %{game | stats: List.replace_at(game.stats, stat_idx, updated)}
      swap_walk(game, tmp)
    else
      {game, stat_idx}
    end
  end

  # Pascal:
  #   MoveStat(statId, X+StepX, Y+StepY);
  #   repeat
  #     tx := X-StepX; ty := Y-StepY; ix := StepX; iy := StepY;
  #     if Follower < 0 then
  #       try link (tx-ix,ty-iy), (tx-iy,ty-ix), (tx+iy,ty+ix)
  #     if Follower > 0 then
  #       Follower.Leader := statId; Follower.P1 := P1; Follower.P2 := P2;
  #       Follower.StepX := tx - Follower.X; Follower.StepY := ty - Follower.Y;
  #       MoveStat(Follower, tx, ty);
  #     statId := Follower;
  #   until statId = -1;
  defp move_and_propagate(game, head_idx) do
    head = Enum.at(game.stats, head_idx)
    nx = head.x + head.step_x
    ny = head.y + head.step_y

    game
    |> Game.move_stat(head_idx, nx, ny)
    |> propagate(head_idx)
  end

  defp propagate(game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    tx = stat.x - stat.step_x
    ty = stat.y - stat.step_y
    ix = stat.step_x
    iy = stat.step_y

    game =
      if stat.follower < 0 do
        link_follower(game, stat_idx, tx, ty, ix, iy)
      else
        game
      end

    stat = Enum.at(game.stats, stat_idx)

    if stat.follower > 0 do
      follower = Enum.at(game.stats, stat.follower)
      new_step_x = tx - follower.x
      new_step_y = ty - follower.y

      game
      |> update_stat(stat.follower, fn s ->
        %Stat{
          s
          | leader: stat_idx,
            p1: stat.p1,
            p2: stat.p2,
            step_x: new_step_x,
            step_y: new_step_y
        }
      end)
      |> Game.move_stat(stat.follower, tx, ty)
      |> propagate(stat.follower)
    else
      game
    end
  end

  # Scan the three tiles adjacent to (tx, ty) that aren't the forward
  # direction the mover just came from. Reference order: behind along
  # motion, then the two perpendicular sides.
  defp link_follower(game, stat_idx, tx, ty, ix, iy) do
    candidates = [
      {tx - ix, ty - iy},
      {tx - iy, ty - ix},
      {tx + iy, ty + ix}
    ]

    case Enum.find_value(candidates, fn {cx, cy} -> unclaimed_segment_at(game, cx, cy) end) do
      nil -> game
      seg_idx -> update_stat(game, stat_idx, fn s -> %Stat{s | follower: seg_idx} end)
    end
  end

  defp unclaimed_segment_at(game, x, y) do
    with {@segment, _} <- Game.tile_at(game, x, y) || :none,
         idx when is_integer(idx) <- find_stat_at(game.stats, x, y),
         %Stat{leader: leader} when leader < 0 <- Enum.at(game.stats, idx) do
      idx
    else
      _ -> nil
    end
  end

  # ---- segment -----------------------------------------------------------

  @doc """
  Segment tick. Inactive while linked. An orphaned segment (`leader < 0`)
  counts its leader down each pass; once it drops past `-1`, the tile is
  promoted to a centipede head.
  """
  @spec segment_tick(Game.t(), non_neg_integer()) :: Game.t()
  def segment_tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)

    cond do
      stat.leader < -1 ->
        promote_tile_to_head(game, stat.x, stat.y)

      stat.leader < 0 ->
        update_stat(game, stat_idx, fn s -> %Stat{s | leader: s.leader - 1} end)

      true ->
        game
    end
  end

  # ---- helpers -----------------------------------------------------------

  defp random_perpendiculars(primary) do
    {dx, dy} = primary
    # `((Random(2)*2) - 1)` yields +1 or -1; applied to the opposing axis
    # so the result is a 90° rotation. The opposite perpendicular is just
    # the negation of the first.
    first = {sign() * dy, sign() * dx}
    {first, negate(first)}
  end

  defp sign, do: :rand.uniform(2) * 2 - 3

  defp negate({x, y}), do: {-x, -y}

  defp set_step(game, stat_idx, sx, sy) do
    update_stat(game, stat_idx, fn s -> %Stat{s | step_x: sx, step_y: sy} end)
  end

  defp update_stat(game, stat_idx, fun) do
    stat = Enum.at(game.stats, stat_idx)
    %{game | stats: List.replace_at(game.stats, stat_idx, fun.(stat))}
  end

  defp put_tile(game, pos, tile), do: %{game | tiles: Map.put(game.tiles, pos, tile)}

  defp promote_tile_to_head(game, x, y) do
    {_, color} = Map.fetch!(game.tiles, {x, y})
    put_tile(game, {x, y}, {@head, color})
  end

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s -> s.x == x and s.y == y end)
  end

  defp player_at?(game, x, y) do
    case Game.tile_at(game, x, y) do
      {@player, _} -> true
      _ -> false
    end
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25
end
