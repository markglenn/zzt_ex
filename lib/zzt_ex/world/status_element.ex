defmodule ZZTEx.World.StatusElement do
  alias ZZTEx.World.Point

  defstruct [
    :location,
    :step_x,
    :step_y,
    :cycle,
    :p1,
    :p2,
    :p3,
    :follower,
    :leader,
    :under_id,
    :under_color,
    :current_instruction,
    :code,
    :code_pointer
  ]

  @type t :: %__MODULE__{
          location: Point.t(),
          step_x: integer,
          step_y: integer,
          cycle: integer,
          p1: arity,
          p2: arity,
          p3: arity,
          follower: t() | nil,
          leader: t() | nil,
          under_id: arity,
          under_color: arity,
          current_instruction: integer,
          code: String.t() | nil,
          code_pointer: non_neg_integer | nil
        }
end
