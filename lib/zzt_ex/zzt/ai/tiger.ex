defmodule ZztEx.Zzt.AI.Tiger do
  @moduledoc """
  One-to-one port of `ElementTigerTick`. Tigers roll for a shot first,
  then delegate to Lion movement.

  Shot roll is `(Random(10) * 3) <= (P2 mod 0x80)` — so the low 7 bits
  of P2 control firing rate. The high bit of P2 picks the projectile:
  Bullet (18) when clear, Star (15) when set.

  Fire order mirrors the reference: if the player is within 2 tiles on
  the X axis, shoot vertically toward them; otherwise, if within 2 on
  Y, shoot horizontally. After the shot attempt (success or not), run
  the Lion movement for the stalking behavior.
  """

  alias ZztEx.Zzt.Game
  alias ZztEx.Zzt.AI.{Directions, Lion}

  @bullet 18
  @star 15

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    element = if stat.p2 >= 0x80, do: @star, else: @bullet

    # `Random(10) * 3` yields {0, 3, 6, 9, ..., 27} — compared against
    # the low 7 bits of P2 so higher P2 means more frequent shots.
    roll = (:rand.uniform(10) - 1) * 3
    rate = rem(stat.p2, 0x80)

    game =
      if roll <= rate do
        try_shot(game, stat, element)
      else
        game
      end

    # Re-acquire the tiger by position before falling through to Lion
    # movement — the shot may have removed other stats and shifted idx.
    case Enum.find_index(game.stats, fn s -> s.x == stat.x and s.y == stat.y end) do
      nil -> game
      idx -> Lion.tick(game, idx)
    end
  end

  defp try_shot(game, stat, element) do
    player = Enum.at(game.stats, 0)

    {game, shot?} =
      if abs(stat.x - player.x) <= 2 do
        Game.board_shoot(
          game,
          stat.x,
          stat.y,
          0,
          Directions.signum(player.y - stat.y),
          1,
          element
        )
      else
        {game, false}
      end

    if shot? do
      game
    else
      if abs(stat.y - player.y) <= 2 do
        {game, _} =
          Game.board_shoot(
            game,
            stat.x,
            stat.y,
            Directions.signum(player.x - stat.x),
            0,
            1,
            element
          )

        game
      else
        game
      end
    end
  end
end
