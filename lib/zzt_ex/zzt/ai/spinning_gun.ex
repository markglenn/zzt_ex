defmodule ZztEx.Zzt.AI.SpinningGun do
  @moduledoc """
  One-to-one port of `ElementSpinningGunTick`. Spinning Guns are
  stationary shooters: they never move but fire projectiles each tick.

      element := if P2 >= $80 then Star else Bullet
      if Random(9) < (P2 mod $80):
        if Random(9) <= P1:
          # smart aim — vertical first if within 2 on X, else horizontal
        else:
          # dumb shot in a random cardinal direction

  `P1` controls intelligence (odds of aiming at the player), `P2` low
  7 bits controls firing rate, high bit toggles between Bullet and Star.
  """

  alias ZztEx.Zzt.Game
  alias ZztEx.Zzt.AI.Directions

  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    element = if stat.p2 >= 0x80, do: 15, else: 18

    if :rand.uniform(9) - 1 < rem(stat.p2, 0x80) do
      fire(game, stat, element)
    else
      game
    end
  end

  defp fire(game, stat, element) do
    if :rand.uniform(9) - 1 <= stat.p1 do
      smart_shot(game, stat, element)
    else
      {dx, dy} = Directions.random_step()
      {game, _} = Game.board_shoot(game, stat.x, stat.y, dx, dy, 1, element)
      game
    end
  end

  defp smart_shot(game, stat, element) do
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
