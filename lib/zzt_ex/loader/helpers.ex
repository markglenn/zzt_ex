defmodule ZZTEx.Loader.Helpers do
  @spec load_fixed_string(binary) :: binary
  def load_fixed_string(<<size::8, str::binary-size(size), _::binary>>), do: str
end
