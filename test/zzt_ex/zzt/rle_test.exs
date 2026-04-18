defmodule ZztEx.Zzt.RleTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.Rle

  test "expands runs of {element, color}" do
    input = <<3, 21, 7, 2, 22, 14>>
    assert {tiles, <<>>} = Rle.decode(input, 5)

    assert tiles == [
             {21, 7},
             {21, 7},
             {21, 7},
             {22, 14},
             {22, 14}
           ]
  end

  test "treats count 0 as 256" do
    input = <<0, 0, 0>>
    {tiles, rest} = Rle.decode(input, 256)
    assert length(tiles) == 256
    assert Enum.all?(tiles, &(&1 == {0, 0}))
    assert rest == <<>>
  end

  test "stops once the tile budget is reached even mid-run" do
    input = <<10, 1, 2, 99, 99, 99>>
    {tiles, rest} = Rle.decode(input, 4)
    assert length(tiles) == 4
    assert Enum.all?(tiles, &(&1 == {1, 2}))
    # The overflow of the first run is dropped; subsequent bytes remain.
    assert rest == <<99, 99, 99>>
  end
end
