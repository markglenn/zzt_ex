defmodule ZZTEx do
  use Bitwise

  alias ZZTEx.World.Board
  alias ZZTEx.Elements.Tick

  @moduledoc """
  ZZTEx keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def run do
    {:ok, %{boards: [board | _]}} = ZZTEx.Loader.ZZTFile.load("priv/worlds/TOWN.ZZT")

    ZZTEx.Game.tick(board)
  end
end
