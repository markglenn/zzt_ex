defmodule ZztExWeb.GameLive.Play do
  @moduledoc """
  Loads a single ZZT world and renders the currently selected board
  alongside the stock ZZT sidebar. An 80x25 CP437 text-mode display with
  a speed slider matching ZZT's original 1-9 settings.
  """
  use ZztExWeb, :live_view

  alias ZztEx.Games
  alias ZztEx.Zzt.{Board, Game, Render, ScrollRender, Sidebar}

  # ZZT's GameSpeeds table: the number of 18.2 Hz BIOS ticks waited between
  # stat passes, per in-game speed setting 1..9. Speed 4 is the default,
  # matching ZZT's default game speed (~220 ms/stat cycle). At speeds 8-9
  # the delay is 0 in stock ZZT; we clamp to one BIOS tick so LiveView
  # isn't re-rendering 1500 spans 60 times a second.
  @speed_bios_ticks %{
    1 => 7,
    2 => 6,
    3 => 5,
    4 => 4,
    5 => 3,
    6 => 2,
    7 => 1,
    8 => 1,
    9 => 1
  }

  @default_speed 4

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Games.load(slug) do
      {:ok, world, listing} ->
        if connected?(socket),
          do: Process.send_after(self(), :tick, interval_ms(@default_speed))

        game = Game.new(world)

        {:ok,
         socket
         |> assign(:slug, slug)
         |> assign(:listing, listing)
         |> assign(:world, world)
         |> assign(:page_title, listing.name)
         |> assign(:speed, @default_speed)
         |> assign(:game, game)
         |> select_board(game.board_index)}

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

  def handle_event("set-speed", %{"speed" => speed}, socket) do
    speed = speed |> String.to_integer() |> min(9) |> max(1)
    {:noreply, assign(socket, :speed, speed)}
  end

  def handle_event("keydown", %{"key" => key} = params, socket) do
    # Don't eat keystrokes while the user is typing into the speed
    # slider (or any future input); Phoenix dispatches keydown globally.
    cond do
      typing_in_form?(params) ->
        {:noreply, socket}

      socket.assigns.game.pending_scroll ->
        handle_scroll_key(key, socket)

      step = arrow_step(key) ->
        {dx, dy} = step
        game = Game.move_player(socket.assigns.game, dx, dy)
        {:noreply, refresh_rows(socket, game)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("dismiss-scroll", _params, socket) do
    game = Game.dismiss_scroll(socket.assigns.game)
    {:noreply, refresh_rows(socket, game)}
  end

  defp handle_scroll_key(key, socket) do
    case key do
      k when k in ["Escape", "Enter", " "] ->
        {:noreply, refresh_rows(socket, Game.dismiss_scroll(socket.assigns.game))}

      "ArrowUp" ->
        {:noreply, refresh_rows(socket, Game.scroll_cursor(socket.assigns.game, -1))}

      "ArrowDown" ->
        {:noreply, refresh_rows(socket, Game.scroll_cursor(socket.assigns.game, 1))}

      "PageUp" ->
        {:noreply, refresh_rows(socket, Game.scroll_cursor(socket.assigns.game, -14))}

      "PageDown" ->
        {:noreply, refresh_rows(socket, Game.scroll_cursor(socket.assigns.game, 14))}

      _ ->
        {:noreply, socket}
    end
  end

  defp arrow_step("ArrowUp"), do: {0, -1}
  defp arrow_step("ArrowDown"), do: {0, 1}
  defp arrow_step("ArrowLeft"), do: {-1, 0}
  defp arrow_step("ArrowRight"), do: {1, 0}
  defp arrow_step(_), do: nil

  defp typing_in_form?(%{"target" => target}) when is_binary(target) do
    target in ~w(input textarea select)
  end

  defp typing_in_form?(_), do: false

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, interval_ms(socket.assigns.speed))
    game = Game.advance(socket.assigns.game)
    {:noreply, refresh_rows(socket, game)}
  end

  defp interval_ms(speed), do: Map.fetch!(@speed_bios_ticks, speed) * 55

  defp select_board(%{assigns: %{world: world, game: game}} = socket, index) do
    last = length(world.boards) - 1
    clamped = index |> max(0) |> min(last)

    new_game =
      if clamped == game.board_index do
        game
      else
        # Switching boards resets the runtime state for that board, just
        # like walking through a board edge in ZZT. Inventory is preserved
        # via the current player map.
        fresh = Game.new(world, clamped)
        %{fresh | player: game.player}
      end

    refresh_rows(socket, new_game)
  end

  defp refresh_rows(socket, game) do
    board = Game.to_board(game)

    socket
    |> assign(:game, game)
    |> assign(:board_index, game.board_index)
    |> assign(:board, game.board)
    |> assign(
      :board_rows,
      Render.rows(board,
        tick: game.stat_tick,
        title_screen?: game.board_index == 0,
        message: game.message && {game.message, game.message_ticks}
      )
    )
    |> assign(:sidebar_rows, Sidebar.rows(game.player))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="zzt-play"
        phx-window-keydown="keydown"
        class="px-4 py-6 flex flex-col items-center gap-4"
      >
        <div class="w-full max-w-6xl flex flex-wrap items-center justify-between gap-3">
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

        <div class="w-fit">
          <.screen board_rows={@board_rows} sidebar_rows={@sidebar_rows} />

          <form phx-change="set-speed" class="mt-3 flex items-center gap-3 text-sm">
            <label for="speed" class="font-mono">Speed</label>
            <input
              type="range"
              name="speed"
              id="speed"
              min="1"
              max="9"
              step="1"
              value={@speed}
              class="w-48 accent-primary"
            />
            <span class="font-mono w-16">
              {@speed} <span class="text-base-content/50">({interval_ms(@speed)}ms)</span>
            </span>
          </form>
        </div>

        <div
          :if={@board.message != ""}
          class="w-full max-w-xl rounded-box border border-base-300 bg-base-200 p-4"
        >
          <h2 class="text-sm font-semibold mb-1">Board Message</h2>
          <p class="font-mono text-xs whitespace-pre-wrap">{@board.message}</p>
        </div>

        <.scroll_window :if={@game.pending_scroll} scroll={@game.pending_scroll} />
      </div>
    </Layouts.app>
    """
  end

  attr :board_rows, :list, required: true
  attr :sidebar_rows, :list, required: true

  defp screen(assigns) do
    ~H"""
    <div class="zzt-screen" aria-label={"ZZT screen, 80 by #{Board.height()}"}>
      <.grid rows={@board_rows} class="zzt-board-grid" />
      <.grid rows={@sidebar_rows} class="zzt-sidebar-grid" />
    </div>
    """
  end

  attr :scroll, :map, required: true

  defp scroll_window(assigns) do
    assigns =
      assign(
        assigns,
        :rows,
        ScrollRender.render(assigns.scroll, line_pos: assigns.scroll.line_pos)
      )

    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
      phx-click="dismiss-scroll"
      role="dialog"
      aria-label={"Scroll: " <> @scroll.title}
    >
      <div class="zzt-scroll-window" phx-click-away="dismiss-scroll">
        <.grid rows={@rows} />
      </div>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :class, :string, default: ""

  defp grid(assigns) do
    ~H"""
    <pre class={["zzt-grid", @class]} phx-no-curly-interpolation><%= for row <- @rows do %><div class="zzt-row"><%= for {char, fg, bg, blink} <- row do %><span class={["zzt-c", "fg#{fg}", "bg#{bg}", blink && "blink"]}><%= char %></span><% end %></div><% end %></pre>
    """
  end
end
