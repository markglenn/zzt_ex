defmodule ZZTEx.Elements.Tick.Centipede do
  import ZZTEx.Elements.Tick, only: [signum: 2, random_direction: 0]

  alias ZZTEx.Elements.ElementType
  alias ZZTEx.World.{Board, StatusElement}

  def tick(%Board{} = board, %StatusElement{} = status_element) do
    {player_x, player_y} =
      board.status_elements
      |> List.first()
      |> Map.get(:location)

    %{location: {x, y}, p1: p1, p2: p2, step_x: step_x, step_y: step_y} = status_element

    {step_x, step_y} =
      cond do
        player_x == x and :random.uniform(10) < p1 ->
          {0, signum(player_y, y)}

        player_y == y and :random.uniform(10) < p1 ->
          {signum(player_x, x), 0}

        :random.uniform(40) < p2 || (step_x == 0 && step_y == 0) ->
          random_direction()

        true ->
          {0, 0}
      end

    x = x + step_x
    y = y + step_y

    tile = Board.tile_at(board, {x, y})

    if ElementType.element(tile.element).walkable do
      %{location: {old_x, old_y}} = status_element
      {board, leader} = Board.move_status(board, status_element, {x, y})
      {board, follower} = find_follower(board, leader)
      move_follower(board, follower, old_x, old_y)
    else
      board
    end
  end

  defp find_follower(board, leader = %StatusElement{follower: nil}) do
    tx = elem(leader.location, 0) - leader.step_x
    ty = elem(leader.location, 1) - leader.step_y
    ix = leader.step_x
    iy = leader.step_y

    [
      {Board.tile_at(board, {tx - ix, ty - iy}), Board.status_at(board, {tx - ix, ty - iy})},
      {Board.tile_at(board, {tx - iy, ty - ix}), Board.status_at(board, {tx - iy, ty - ix})},
      {Board.tile_at(board, {tx + ix, ty + iy}), Board.status_at(board, {tx + ix, ty + iy})}
    ]
    |> Enum.filter(&(!is_nil(elem(&1, 1))))
    |> Enum.filter(fn {tile, _status} ->
      ElementType.element(tile.element).element_type == :segment
    end)
    |> Enum.find(&is_nil(elem(&1, 1).leader))
    |> case do
      nil ->
        {board, nil}

      {_, segment} ->
        idx = Board.index_of(board, segment)
        leader_idx = Board.index_of(board, leader)

        segment = %{segment | leader: leader}

        status_elements =
          board.status_elements
          |> List.replace_at(idx, segment)
          |> List.replace_at(leader_idx, %{leader | follower: segment})

        board = %{board | status_elements: status_elements}
        {board, segment}
    end
  end

  defp find_follower(board, %{follower: follower}), do: {board, follower}

  defp move_follower(board, nil, _x, _y), do: board

  defp move_follower(board, follower, x, y) do
    %{location: {old_x, old_y}} = follower

    {board, leader} =
      board
      |> Board.move_status(follower, {x, y})

    {board, follower} = find_follower(board, leader)

    board
    |> move_follower(follower, old_x, old_y)
  end
end
