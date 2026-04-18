defmodule ZztExWeb.GameLive.Play do
  @moduledoc """
  Loads a single ZZT world and renders the currently selected board.

  This is the foundation LiveView — it parses the world, shows the grid
  using the ZZT palette and CP437 font, and lets the player flip through
  boards. Input handling and game simulation arrive in subsequent changes.
  """
  use ZztExWeb, :live_view

  alias ZztEx.Games
  alias ZztEx.Zzt.{Board, Render, World}

  # ZZT runs at ~9 Hz natively; 125ms (8 fps) is close enough for
  # star/conveyor/transporter cycling without hammering LiveView diffs.
  @tick_interval_ms 125

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Games.load(slug) do
      {:ok, world, listing} ->
        if connected?(socket), do: Process.send_after(self(), :tick, @tick_interval_ms)

        {:ok,
         socket
         |> assign(:slug, slug)
         |> assign(:listing, listing)
         |> assign(:world, world)
         |> assign(:page_title, listing.name)
         |> assign(:tick, 0)
         |> select_board(world.current_board)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Could not load that world.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("select-board", %{"index" => index}, socket) do
    {:noreply, select_board(socket, String.to_integer(index))}
  end

  def handle_event("next-board", _params, socket) do
    {:noreply, select_board(socket, socket.assigns.board_index + 1)}
  end

  def handle_event("prev-board", _params, socket) do
    {:noreply, select_board(socket, socket.assigns.board_index - 1)}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_interval_ms)
    tick = socket.assigns.tick + 1

    rows =
      Render.rows(socket.assigns.board,
        tick: tick,
        title_screen?: socket.assigns.board_index == 0
      )

    {:noreply, assign(socket, tick: tick, rows: rows)}
  end

  defp select_board(%{assigns: %{world: world}} = socket, index) do
    last = length(world.boards) - 1
    clamped = index |> max(0) |> min(last)
    board = World.board(world, clamped)

    socket
    |> assign(:board_index, clamped)
    |> assign(:board, board)
    |> assign(
      :rows,
      Render.rows(board, tick: socket.assigns.tick, title_screen?: clamped == 0)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-6xl px-4 py-6">
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div>
            <.link navigate={~p"/"} class="text-xs text-base-content/60 hover:text-base-content">
              ← Library
            </.link>
            <h1 class="text-2xl font-bold">{@listing.name}</h1>
            <p class="text-sm text-base-content/60">
              Board {@board_index + 1} of {length(@world.boards)} —
              <span class="font-mono">{@board.title}</span>
            </p>
          </div>

          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="prev-board"
              disabled={@board_index == 0}
              class="rounded-field border border-base-300 bg-base-200 px-3 py-1.5 text-sm font-semibold transition hover:bg-base-300 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              ◀ Prev
            </button>
            <button
              type="button"
              phx-click="next-board"
              disabled={@board_index == length(@world.boards) - 1}
              class="rounded-field border border-base-300 bg-base-200 px-3 py-1.5 text-sm font-semibold transition hover:bg-base-300 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              Next ▶
            </button>
          </div>
        </div>

        <div class="flex flex-col items-center gap-4 lg:flex-row lg:items-start">
          <.board_view rows={@rows} />

          <aside class="w-full lg:w-64 text-sm">
            <div class="rounded-box border border-base-300 bg-base-200 p-4">
              <h2 class="font-semibold mb-2">Player</h2>
              <dl class="grid grid-cols-2 gap-y-1 font-mono text-xs">
                <dt class="text-base-content/60">Health</dt>
                <dd>{@world.health}</dd>
                <dt class="text-base-content/60">Ammo</dt>
                <dd>{@world.ammo}</dd>
                <dt class="text-base-content/60">Gems</dt>
                <dd>{@world.gems}</dd>
                <dt class="text-base-content/60">Torches</dt>
                <dd>{@world.torches}</dd>
                <dt class="text-base-content/60">Score</dt>
                <dd>{@world.score}</dd>
              </dl>
            </div>
            <div
              :if={@board.message != ""}
              class="mt-3 rounded-box border border-base-300 bg-base-200 p-4"
            >
              <h2 class="font-semibold mb-1">Board Message</h2>
              <p class="font-mono text-xs whitespace-pre-wrap">{@board.message}</p>
            </div>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :rows, :list, required: true

  defp board_view(assigns) do
    ~H"""
    <div class="zzt-board" aria-label={"ZZT board, #{Board.width()} by #{Board.height()}"}>
      <pre class="zzt-grid" phx-no-curly-interpolation><%= for row <- @rows do %><div class="zzt-row"><%= for {char, fg, bg, blink} <- row do %><span class={["zzt-c", "fg#{fg}", "bg#{bg}", blink && "blink"]}><%= char %></span><% end %></div><% end %></pre>
    </div>
    """
  end
end
