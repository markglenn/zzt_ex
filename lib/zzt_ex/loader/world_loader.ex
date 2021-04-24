defmodule ZZTEx.Loader.WorldLoader do
  alias ZZTEx.World

  alias ZZTEx.Loader.BoardLoader

  import ZZTEx.Loader.Helpers

  @spec load(binary) :: {:ok, World.t()}
  def load(<<0xFF, 0xFF, header::binary-size(510), rest::binary>>) do
    with {:ok, world} <- load_zzt_header(header),
         {:ok, boards, <<>>} <- BoardLoader.load_boards(world.num_boards + 1, rest) do
      {:ok, %{world | boards: boards}}
    end
  end

  @spec load_zzt_header(binary) :: {:ok, World.t()}
  def load_zzt_header(<<
        num_boards::signed-little-size(16),
        player_ammo::signed-little-size(16),
        player_gems::signed-little-size(16),
        keys::binary-size(7),
        player_health::signed-little-size(16),
        player_board::signed-little-size(16),
        player_torches::signed-little-size(16),
        torch_cycles::signed-little-size(16),
        energy_cycles::signed-little-size(16),
        _::size(16),
        player_score::signed-little-size(16),
        world_name::binary-size(21),
        flags::binary-size(210),
        time_passed::signed-little-size(16),
        time_passed_ticks::signed-little-size(16),
        locked::size(8),
        _ignored::binary-size(14),
        _padding::binary
      >>) do
    {:ok,
     %ZZTEx.World{
       num_boards: num_boards,
       player_ammo: player_ammo,
       keys: load_keys(keys),
       player_gems: player_gems,
       player_health: player_health,
       player_board: player_board,
       player_torches: player_torches,
       torch_cycles: torch_cycles,
       energy_cycles: energy_cycles,
       player_score: player_score,
       world_name: load_fixed_string(world_name),
       flags: load_flags({}, flags),
       time_passed: time_passed,
       time_passed_ticks: time_passed_ticks,
       locked: locked != 0,
       boards: []
     }}
  end

  @spec load_keys(binary) :: World.keys_t()
  defp load_keys(<<blue, green, cyan, red, purple, yellow, white>>) do
    %{
      blue: blue != 0,
      green: green != 0,
      cyan: cyan != 0,
      red: red != 0,
      purple: purple != 0,
      yellow: yellow != 0,
      white: white != 0
    }
  end

  @spec load_flags(tuple, binary) :: World.flag_t()
  defp load_flags(flags, <<>>), do: flags

  defp load_flags(flags, <<flag::binary-size(21), rest::binary>>) do
    Tuple.append(flags, load_fixed_string(flag))
    |> load_flags(rest)
  end
end
