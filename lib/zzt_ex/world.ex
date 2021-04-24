defmodule ZZTEx.World do
  alias ZZTEx.World.{Board, Keys}

  defstruct [
    :num_boards,
    :player_ammo,
    :player_gems,
    :keys,
    :player_health,
    :player_board,
    :player_torches,
    :torch_cycles,
    :energy_cycles,
    :player_score,
    :world_name,
    :flags,
    :time_passed,
    :time_passed_ticks,
    :locked,
    :boards
  ]

  @type flag_t :: {binary, binary, binary, binary, binary, binary, binary, binary, binary, binary}
  @type point :: {integer, integer}

  @type t :: %__MODULE__{
          num_boards: integer(),
          player_ammo: integer(),
          player_gems: integer(),
          keys: Keys.t(),
          player_health: integer(),
          player_board: integer(),
          player_torches: integer(),
          torch_cycles: integer(),
          energy_cycles: integer(),
          player_score: integer(),
          world_name: binary,
          flags: flag_t,
          time_passed: integer(),
          time_passed_ticks: integer(),
          locked: boolean(),
          boards: [Board.t()]
        }
end
