defmodule ZZTEx.Loader.ZZTFile do
  alias ZZTEx.Loader.WorldLoader

  @spec load(binary) :: {:error, String.t()} | {:ok, ZZTEx.World.t()}
  def load(path) when is_binary(path) do
    with {:ok, zzt_file} <- File.read(path) do
      WorldLoader.load(zzt_file)
    else
      {:error, reason} -> {:error, :file.format_error(reason) |> to_string()}
    end
  end
end
