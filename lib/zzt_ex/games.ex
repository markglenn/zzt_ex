defmodule ZztEx.Games do
  @moduledoc """
  The installed ZZT games library.

  Worlds are discovered by scanning a directory (by default `priv/games/`)
  for `.zzt` files. The slug used in URLs is the filename without its
  extension, lowercased.
  """

  alias ZztEx.Zzt.World

  @type listing :: %{
          slug: String.t(),
          filename: String.t(),
          name: String.t(),
          board_count: pos_integer(),
          path: Path.t()
        }

  @doc """
  Directory scanned for installed worlds. Configurable via
  `config :zzt_ex, :games_dir`.
  """
  @spec games_dir() :: Path.t()
  def games_dir do
    case Application.get_env(:zzt_ex, :games_dir) do
      nil -> Application.app_dir(:zzt_ex, "priv/games")
      dir -> dir
    end
  end

  @doc """
  Return every installed world's metadata, sorted by display name. Worlds
  that fail to parse are skipped so one bad file doesn't break the index.
  """
  @spec list() :: [listing()]
  def list do
    dir = games_dir()

    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(String.downcase(&1), ".zzt"))
        |> Enum.flat_map(fn entry ->
          path = Path.join(dir, entry)

          case World.load(path) do
            {:ok, world} ->
              [
                %{
                  slug: slug_for(entry),
                  filename: entry,
                  name: display_name(world, entry),
                  board_count: length(world.boards),
                  path: path
                }
              ]

            {:error, _} ->
              []
          end
        end)
        |> Enum.sort_by(& &1.name)

      {:error, _} ->
        []
    end
  end

  @doc """
  Load a single world by slug. Returns `{:ok, world, listing}` or `:error`.
  """
  @spec load(String.t()) :: {:ok, World.t(), listing()} | :error
  def load(slug) do
    with %{} = listing <- Enum.find(list(), &(&1.slug == slug)),
         {:ok, world} <- World.load(listing.path) do
      {:ok, world, listing}
    else
      _ -> :error
    end
  end

  defp slug_for(filename) do
    filename
    |> Path.rootname()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp display_name(%World{name: name}, fallback) when is_binary(name) do
    case String.trim(name) do
      "" -> Path.rootname(fallback)
      name -> name
    end
  end
end
