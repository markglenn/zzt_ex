defmodule ZZTEx.World.Keys do
  defstruct [:blue, :green, :cyan, :red, :purple, :yellow, :white]

  @type t :: %{
          blue: boolean(),
          green: boolean(),
          cyan: boolean(),
          red: boolean(),
          purple: boolean(),
          yellow: boolean(),
          white: boolean()
        }
end
