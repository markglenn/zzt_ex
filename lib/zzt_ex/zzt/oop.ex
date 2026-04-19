defmodule ZztEx.Zzt.Oop do
  @moduledoc """
  A bytecode-style interpreter for ZZT-OOP — the scripting language
  that drives Objects (element 36). Initial cut covers the commands
  the bank-vault puzzle in town.zzt leans on, with room for the rest
  of the command set to land incrementally.

  Supported so far:

    * `@name`                          — object name header (no-op here).
    * `'comment`                       — comment line.
    * `:label`                         — jump target.
    * Plain text lines                 — skipped for now (scroll display
      comes in a follow-up).
    * `/<dir>` / `?<dir>`              — walk. `/` keeps retrying next
      tick if blocked; `?` gives up after one attempt.
    * `#end`                           — halt permanently.
    * `#idle`                          — halt for one tick.
    * `#die`                           — remove the stat.
    * `#walk <dir>`                    — set the stat's step vector.
    * `#go <dir>` / `#try <dir>`       — single-tick movement attempt.
      `#go` retries next tick if blocked; `#try` falls through and keeps
      parsing (enabling `#try e fail` → `:fail`).
    * `#send <target>:<label>` or      — dispatch a label on self.
      bare `#<label>`                    Remote object sends land later.
    * Unknown words                    — treated as `#send <word>` so
      bare `#fail` → `:fail` branches work.

  Execution is driven by a byte offset (`stat.instruction`) into
  `stat.code`, matching the reference's position-based layout. Each
  tick runs instructions until something halting fires or 32 ops have
  executed (the reference's anti-infinite-loop cap).
  """

  alias ZztEx.Zzt.{Element, Game, Stat}

  @max_ops_per_tick 32

  @type step :: {-1 | 0 | 1, -1 | 0 | 1}

  @doc """
  Advance the OOP program for the stat at `stat_idx`. Returns the
  updated game.
  """
  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)

    if stat.instruction < 0 do
      # Already halted permanently (reached #end or end-of-program).
      game
    else
      run(game, stat_idx, stat.instruction, 0)
    end
  end

  # ---- Main loop ---------------------------------------------------------

  # Cap instructions per tick so a rogue #send loop can't wedge the game
  # (matches the reference's `insCount > 32` guard).
  defp run(game, stat_idx, pos, ops) when ops >= @max_ops_per_tick,
    do: save_position(game, stat_idx, pos)

  defp run(game, stat_idx, pos, ops) do
    stat = Enum.at(game.stats, stat_idx)

    case read_line(stat.code, pos) do
      :eof ->
        halt_permanently(game, stat_idx)

      {line, next_pos} ->
        dispatch_line(game, stat_idx, line, pos, next_pos, ops)
    end
  end

  defp dispatch_line(game, stat_idx, line, pos, next_pos, ops) do
    case classify(line) do
      :skip ->
        run(game, stat_idx, next_pos, ops + 1)

      {:walk, step, repeat?} ->
        walk(game, stat_idx, pos, next_pos, step, repeat?)

      {:commands, cmds} ->
        execute_commands(game, stat_idx, cmds, pos, next_pos, ops)
    end
  end

  defp halt_permanently(game, stat_idx), do: save_position(game, stat_idx, -1)

  defp save_position(game, stat_idx, pos) do
    stat = Enum.at(game.stats, stat_idx)
    %{game | stats: List.replace_at(game.stats, stat_idx, %Stat{stat | instruction: pos})}
  end

  # ---- Line classification ----------------------------------------------

  defp classify(line) do
    text = String.trim_leading(line, " ")

    cond do
      text == "" ->
        :skip

      String.starts_with?(text, "@") ->
        :skip

      String.starts_with?(text, "'") ->
        :skip

      String.starts_with?(text, ":") ->
        :skip

      String.starts_with?(text, "/") ->
        walk_line(text, true)

      String.starts_with?(text, "?") ->
        walk_line(text, false)

      String.starts_with?(text, "#") ->
        {:commands, tokenize_commands(String.slice(text, 1..-1//1))}

      true ->
        :skip
    end
  end

  defp walk_line(<<_sigil, dir_char, _rest::binary>>, repeat?) do
    case direction(<<dir_char>>) do
      nil -> :skip
      step -> {:walk, step, repeat?}
    end
  end

  defp walk_line(_short, _repeat?), do: :skip

  # Flatten a `#...` line into an ordered list of command ops. `#try e fail`
  # → `[{:try_dir, {1, 0}}, {:send, "fail"}]`.
  defp tokenize_commands(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> collect([])
  end

  defp collect([], acc), do: Enum.reverse(acc)

  defp collect([word | rest], acc) do
    up = String.upcase(word)

    case up do
      "END" -> Enum.reverse([:end | acc])
      "IDLE" -> Enum.reverse([:idle | acc])
      "DIE" -> Enum.reverse([:die | acc])
      "THEN" -> collect(rest, acc)
      "WALK" -> read_direction(rest, :walk, acc)
      "GO" -> read_direction(rest, :go, acc)
      "TRY" -> read_direction(rest, :try_dir, acc)
      _ -> collect(rest, [{:send, word} | acc])
    end
  end

  defp read_direction([dir | rest], op, acc) do
    case direction(dir) do
      nil -> collect(rest, acc)
      step -> collect(rest, [{op, step} | acc])
    end
  end

  defp read_direction([], _op, acc), do: Enum.reverse(acc)

  defp direction(s) do
    case String.upcase(s) do
      "N" -> {0, -1}
      "NORTH" -> {0, -1}
      "S" -> {0, 1}
      "SOUTH" -> {0, 1}
      "E" -> {1, 0}
      "EAST" -> {1, 0}
      "W" -> {-1, 0}
      "WEST" -> {-1, 0}
      "I" -> {0, 0}
      "IDLE" -> {0, 0}
      _ -> nil
    end
  end

  # ---- Walk (/dir, ?dir) -------------------------------------------------

  defp walk(game, stat_idx, _current_pos, next_pos, {0, 0}, _repeat?) do
    # Idle direction halts for a tick and advances.
    save_position(game, stat_idx, next_pos)
  end

  defp walk(game, stat_idx, current_pos, next_pos, {dx, dy}, repeat?) do
    stat = Enum.at(game.stats, stat_idx)
    tx = stat.x + dx
    ty = stat.y + dy

    if walkable_target?(game, tx, ty) do
      game
      |> Game.move_stat(stat_idx, tx, ty)
      |> save_position(stat_idx, next_pos)
    else
      save_pos = if repeat?, do: current_pos, else: next_pos
      save_position(game, stat_idx, save_pos)
    end
  end

  defp walkable_target?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {elem, _} -> Element.walkable?(elem)
    end
  end

  # ---- Command execution -------------------------------------------------

  defp execute_commands(game, stat_idx, [], _pos, next_pos, ops),
    do: run(game, stat_idx, next_pos, ops + 1)

  defp execute_commands(game, stat_idx, [cmd | rest], pos, next_pos, ops) do
    {new_game, action} = execute_one(game, stat_idx, cmd)

    case action do
      :halt_permanent ->
        halt_permanently(new_game, stat_idx)

      {:halt_tick, :next} ->
        save_position(new_game, stat_idx, next_pos)

      {:halt_tick, :current} ->
        save_position(new_game, stat_idx, pos)

      :die ->
        Game.remove_stat(new_game, stat_idx)

      {:jump, new_pos} ->
        run(new_game, stat_idx, new_pos, ops + 1)

      :fail ->
        execute_commands(new_game, stat_idx, rest, pos, next_pos, ops + 1)

      :continue ->
        execute_commands(new_game, stat_idx, rest, pos, next_pos, ops + 1)
    end
  end

  defp execute_one(game, _stat_idx, :end), do: {game, :halt_permanent}
  defp execute_one(game, _stat_idx, :idle), do: {game, {:halt_tick, :next}}
  defp execute_one(game, _stat_idx, :die), do: {game, :die}

  defp execute_one(game, stat_idx, {:walk, {dx, dy}}) do
    stat = Enum.at(game.stats, stat_idx)
    updated = %Stat{stat | step_x: dx, step_y: dy}
    {%{game | stats: List.replace_at(game.stats, stat_idx, updated)}, :continue}
  end

  defp execute_one(game, stat_idx, {:go, {dx, dy}}) do
    stat = Enum.at(game.stats, stat_idx)

    if walkable_target?(game, stat.x + dx, stat.y + dy) do
      {Game.move_stat(game, stat_idx, stat.x + dx, stat.y + dy), {:halt_tick, :next}}
    else
      # `#go` retries the same instruction next tick when blocked.
      {game, {:halt_tick, :current}}
    end
  end

  defp execute_one(game, stat_idx, {:try_dir, {dx, dy}}) do
    stat = Enum.at(game.stats, stat_idx)

    if walkable_target?(game, stat.x + dx, stat.y + dy) do
      {Game.move_stat(game, stat_idx, stat.x + dx, stat.y + dy), {:halt_tick, :next}}
    else
      # Blocked: fall through to the rest of the command line so that
      # `#try e fail` can reach its trailing `#send fail`.
      {game, :fail}
    end
  end

  defp execute_one(game, stat_idx, {:send, target}) do
    case find_label(game, stat_idx, target) do
      {:local, pos} -> {game, {:jump, pos}}
      _ -> {game, :continue}
    end
  end

  # ---- Label lookup ------------------------------------------------------

  @doc false
  def find_label(%Game{} = game, stat_idx, target) do
    stat = Enum.at(game.stats, stat_idx)

    case String.split(target, ":", parts: 2) do
      [just_label] -> find_in_self(stat, just_label)
      ["", just_label] -> find_in_self(stat, just_label)
      [_remote_name, _label] -> :not_found
    end
  end

  defp find_in_self(%Stat{code: code}, label) do
    label_upper = label |> String.trim() |> String.upcase()
    search_label(code, 0, label_upper)
  end

  defp search_label(code, pos, label_upper) do
    case read_line(code, pos) do
      :eof ->
        :not_found

      {line, next_pos} ->
        trimmed = String.trim_leading(line, " ")

        case trimmed do
          ":" <> rest ->
            name = rest |> String.trim() |> String.upcase()

            if name == label_upper do
              {:local, next_pos}
            else
              search_label(code, next_pos, label_upper)
            end

          _ ->
            search_label(code, next_pos, label_upper)
        end
    end
  end

  # ---- Low-level code reader --------------------------------------------

  @doc false
  def read_line(code, pos) when pos >= byte_size(code), do: :eof

  def read_line(code, pos) do
    do_read_line(code, pos, byte_size(code), [])
  end

  defp do_read_line(_code, pos, size, []) when pos >= size, do: :eof

  defp do_read_line(_code, pos, size, acc) when pos >= size do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), size}
  end

  defp do_read_line(code, pos, size, acc) do
    case :binary.at(code, pos) do
      0 ->
        case acc do
          [] -> :eof
          _ -> {acc |> Enum.reverse() |> IO.iodata_to_binary(), size}
        end

      13 ->
        {acc |> Enum.reverse() |> IO.iodata_to_binary(), pos + 1}

      byte ->
        do_read_line(code, pos + 1, size, [byte | acc])
    end
  end
end
