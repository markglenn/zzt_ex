defmodule ZZTEx.Loader.StatusElementLoader do
  alias ZZTEx.World.StatusElement

  @spec load_status_elements(binary) :: {:ok, [StatusElement.t()]}
  def load_status_elements(<<count::signed-little-size(16), contents::binary>>) do
    with {:ok, status_elements} <- do_load_status_elements([], count + 1, contents) do
      {:ok, status_elements}
    end
  end

  @spec do_load_status_elements(list, non_neg_integer, binary) :: {:ok, list}
  defp do_load_status_elements(elements, 0, <<>>), do: {:ok, Enum.reverse(elements)}

  defp do_load_status_elements(elements, count, rest) do
    {:ok, status_element, rest} = load_status_element(rest)

    [status_element | elements]
    |> do_load_status_elements(count - 1, rest)
  end

  @spec load_status_element(<<_::64, _::_*8>>) :: {:ok, StatusElement.t(), binary}
  defp load_status_element(<<
         location_x::8,
         location_y::8,
         step_x::signed-little-size(16),
         step_y::signed-little-size(16),
         cycle::signed-little-size(16),
         p1::8,
         p2::8,
         p3::8,
         _follower::signed-little-size(16),
         _leader::signed-little-size(16),
         under_id::8,
         under_color::8,
         _pointer::signed-little-size(32),
         current_instruction::signed-little-size(16),
         length::signed-little-size(16),
         _padding::binary-size(8),
         rest::binary
       >>) do
    {code, code_pointer, rest} =
      cond do
        length > 0 ->
          <<code::binary-size(length), rest::binary>> = rest
          {code, nil, rest}

        length < 0 ->
          {nil, abs(length), rest}

        true ->
          {nil, nil, rest}
      end

    {:ok,
     %StatusElement{
       location: {location_x - 1, location_y - 1},
       step_x: step_x,
       step_y: step_y,
       cycle: cycle,
       p1: p1,
       p2: p2,
       p3: p3,
       # follower,
       follower: nil,
       # leader,
       leader: nil,
       under_id: under_id,
       under_color: under_color,
       current_instruction: current_instruction,
       code: code,
       code_pointer: code_pointer
     }, rest}
  end
end
