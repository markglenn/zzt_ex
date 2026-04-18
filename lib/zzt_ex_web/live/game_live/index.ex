defmodule ZztExWeb.GameLive.Index do
  @moduledoc """
  Shows the installed ZZT games library.
  """
  use ZztExWeb, :live_view

  alias ZztEx.Games

  @impl true
  def mount(_params, _session, socket) do
    games = Games.list()

    socket =
      socket
      |> assign(:page_title, "ZZT Library")
      |> assign(:games_dir, Games.games_dir())
      |> stream_configure(:games, dom_id: &"game-#{&1.slug}")
      |> stream(:games, games)
      |> assign(:empty?, games == [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-5xl px-4 py-10">
        <header class="mb-8">
          <h1 class="text-3xl font-bold tracking-tight">ZZT Library</h1>
          <p class="mt-2 text-base-content/70">
            Pick an installed world to load.
          </p>
          <p class="mt-1 text-xs font-mono text-base-content/50">
            Drop <code>.zzt</code>
            files into <code class="px-1 rounded bg-base-200">{@games_dir}</code>
          </p>
        </header>

        <div :if={@empty?} class="rounded-box border border-base-300 bg-base-200 p-8 text-center">
          <p class="text-lg font-semibold">No games installed yet</p>
          <p class="mt-1 text-sm text-base-content/70">
            Place a <code>.zzt</code> world file in the directory above and refresh.
          </p>
        </div>

        <ul
          id="games"
          phx-update="stream"
          class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3"
        >
          <li
            :for={{dom_id, game} <- @streams.games}
            id={dom_id}
            class="group"
          >
            <.link
              navigate={~p"/play/#{game.slug}"}
              class="block rounded-box border border-base-300 bg-base-200 p-4 transition hover:border-primary hover:bg-base-300"
            >
              <p class="font-semibold truncate">{game.name}</p>
              <p class="mt-1 text-xs font-mono text-base-content/60 truncate">
                {game.filename} · {game.board_count} boards
              </p>
            </.link>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
