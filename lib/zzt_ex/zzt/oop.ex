defmodule ZztEx.Zzt.Oop do
  @moduledoc """
  ZZT-OOP interpreter — the scripting language that drives Objects
  (element 36). Ports `OopExecute` from `reconstruction-of-zzt`
  character-for-character so existing worlds' scripts behave the way
  they did in 1991.

  ## Parser model

  Execution is a character stream over `stat.code`. `stat.instruction`
  is the read position. Each tick runs up to 32 commands, halting when
  something explicit (`#end`, `#idle`, `/dir`, `#go`, etc.) sets
  `stop_running`, or when we hit end-of-program or 32 ops.

  ## Commands

    * Text accumulation — plain lines, blank lines, and `$centered` get
      queued; at end-of-tick they render as a scroll (multi-line) or
      flash in the sidebar (single line).
    * Movement — `/dir` / `?dir` / `#go dir` / `#try dir` attempt
      pushes before walking; `#walk dir` just sets `step_x/step_y`.
    * Flow — `#end`, `#idle`, `#die`, `#restart`, `#send target[:label]`,
      `#zap :label`, `#restore :label`, `#if <condition>`,
      `#lock` / `#unlock`.
    * World — `#set flag`, `#clear flag`, `#give counter n`,
      `#take counter n`, `#endgame`.
    * Tiles — `#become tile`, `#put dir tile`, `#change from to`,
      `#char n`, `#cycle n`, `#bind name`.
    * Weapons — `#shoot dir`, `#throwstar dir`.
    * Directions — `N/S/E/W/I/IDLE` plus `SEEK/FLOW/RND/RNDNS/RNDNE`
      and modifiers `CW/CCW/OPP/RNDP`.
    * Conditions — `NOT`, `ALLIGNED`, `CONTACT`, `BLOCKED dir`,
      `ENERGIZED`, `ANY tile`, and bare flag names.

  `:TOUCH`, `:SHOT`, `:ENERGIZE`, `:THUD`, `:BOMBED` are sent externally
  by the game engine when the relevant event fires on this object.
  """

  alias ZztEx.Zzt.{Element, Game, Stat}
  alias ZztEx.Zzt.AI.Directions

  @max_ops_per_tick 32
  @bullet 18
  @star 15
  @player 4

  @doc "Advance the OOP program for the stat at `stat_idx`."
  @spec tick(Game.t(), non_neg_integer()) :: Game.t()
  def tick(%Game{} = game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)
    if stat.instruction < 0, do: game, else: execute(game, stat_idx, stat.instruction)
  end

  @doc """
  Dispatch `label` on the stat at `stat_idx`. Negative stat ids mean
  "engine-triggered" (TOUCH, SHOT, etc.); those respect the object's
  lock (P2 = 1) for its own labels — matching the reference's
  `respectSelfLock` flag.
  """
  @spec send(Game.t(), integer(), String.t()) :: Game.t()
  def send(%Game{} = game, stat_id, label) do
    {game, _sent_to_self?} = do_send(game, stat_id, label, false)
    game
  end

  # ---- Main execute loop -------------------------------------------------

  defp execute(game, stat_idx, position) do
    stat = Enum.at(game.stats, stat_idx)

    state = %{
      game: game,
      stat_idx: stat_idx,
      code: stat.code,
      code_size: byte_size(stat.code),
      position: position,
      last_position: position,
      ops: 0,
      stop_running: false,
      repeat_ins_next_tick: false,
      replace_stat: false,
      replace_tile: nil,
      end_of_program: false,
      line_finished: true,
      text_lines: [],
      last_char: 0
    }

    state
    |> run()
    |> finalize()
  end

  defp run(state) do
    cond do
      state.stop_running -> state
      state.end_of_program -> state
      state.replace_stat -> state
      state.ops > @max_ops_per_tick -> state
      true -> state |> read_instruction() |> run()
    end
  end

  defp read_instruction(state) do
    state = %{state | line_finished: true, last_position: state.position}
    {ch, state} = read_char(state)

    # Skip any number of consecutive label lines.
    {ch, state} = skip_label_lines(ch, state)

    cond do
      ch == 0 ->
        %{state | end_of_program: true, last_char: ch}

      ch == ?' or ch == ?@ ->
        skip_line(%{state | last_char: ch})

      ch == ?/ or ch == ?? ->
        handle_walk_token(ch, state)

      ch == ?# ->
        handle_command(%{state | last_char: ch})

      ch == 13 ->
        # Blank line inside text → an empty paragraph break, but only
        # once we've started accumulating.
        if state.text_lines == [] do
          %{state | last_char: ch}
        else
          %{state | text_lines: ["" | state.text_lines], last_char: ch}
        end

      true ->
        # Plain text line — prepend the char we just read, then append.
        {rest, state} = read_line_to_end(state)
        line = <<ch>> <> rest
        %{state | text_lines: [line | state.text_lines], last_char: ch}
    end
  end

  defp skip_label_lines(?:, state) do
    state = skip_line(state)
    {ch, state} = read_char(state)
    skip_label_lines(ch, state)
  end

  defp skip_label_lines(ch, state), do: {ch, state}

  # ---- Walk tokens (/dir, ?dir) -----------------------------------------

  defp handle_walk_token(sigil, state) do
    repeat? = sigil == ?/
    {word, state} = read_word(state)

    case parse_direction(word, state) do
      {:ok, 0, 0, state} ->
        # /IDLE or ?IDLE — halt for a tick, advance past newline.
        state = maybe_backtrack_newline(state)
        %{state | stop_running: true, repeat_ins_next_tick: false, last_char: 0}

      {:ok, dx, dy, state} ->
        state = try_move(state, dx, dy)

        state =
          if state.moved do
            %{state | repeat_ins_next_tick: false}
          else
            %{state | repeat_ins_next_tick: repeat?}
          end
          |> Map.delete(:moved)

        state = maybe_backtrack_newline(state)
        %{state | stop_running: true}

      {:error, state} ->
        # Reference would OopError; we just halt and advance.
        skip_line(%{state | stop_running: true})
    end
  end

  # The reference reads one more char after the direction word, and if
  # it's not CR it decrements position so the outer loop sees it next.
  # We mirror that: if the next byte is CR, consume it; otherwise leave
  # position alone so skip_line/read_instruction can pick it up.
  defp maybe_backtrack_newline(state) do
    {ch, state2} = read_char(state)
    if ch == 13, do: state2, else: state
  end

  defp try_move(state, dx, dy) do
    stat = current_stat(state)
    tx = stat.x + dx
    ty = stat.y + dy

    game =
      if walkable?(state.game, tx, ty) do
        state.game
      else
        Game.push_tile(state.game, tx, ty, dx, dy)
      end

    if walkable?(game, tx, ty) do
      game = Game.move_stat(game, state.stat_idx, tx, ty)
      Map.merge(state, %{game: game, moved: true})
    else
      Map.merge(state, %{game: game, moved: false})
    end
  end

  # ---- Command (#...) handling ------------------------------------------

  defp handle_command(state) do
    state = read_command(state)

    # Reference runs `OopSkipLine` unconditionally when lineFinished is
    # true — even when stopRunning is set. Otherwise trailing args like
    # the label in `#try e fail` leak into the next tick's parser (and
    # the text accumulator, which is how both "fail" and "vault open"
    # messages end up on-screen).
    if state.line_finished, do: skip_line(state), else: state
  end

  # Read one command word and dispatch. Commands that continue reading
  # further words on the same line (IF true, TRY blocked, GIVE/TAKE
  # underflow) recurse into read_command themselves.
  defp read_command(state) do
    {word, state} = read_word(state)

    {word, state} =
      if word == "THEN" do
        {w, s} = read_word(state)
        {w, s}
      else
        {word, state}
      end

    cond do
      word == "" ->
        # Empty word at a non-terminator means we hit a `#` mid-line
        # (e.g. `#if a #set b`). Consume it and try the next command —
        # mirrors the reference's `if length(OopWord)=0 then goto ReadInstruction`
        # which loops around and re-enters command mode.
        {peek, _} = peek_char(state)

        if peek == ?# do
          {_, state} = read_char(state)
          read_command(state)
        else
          state
        end

      true ->
        state = %{state | ops: state.ops + 1}
        dispatch_command(word, state)
    end
  end

  defp peek_char(state) do
    if state.position >= state.code_size do
      {0, state}
    else
      {:binary.at(state.code, state.position), state}
    end
  end

  defp dispatch_command(word, state) do
    case word do
      "GO" -> cmd_go(state)
      "TRY" -> cmd_try(state)
      "WALK" -> cmd_walk(state)
      "SET" -> cmd_set(state)
      "CLEAR" -> cmd_clear(state)
      "IF" -> cmd_if(state)
      "SHOOT" -> cmd_shoot(state, @bullet)
      "THROWSTAR" -> cmd_shoot(state, @star)
      "GIVE" -> cmd_give_take(state, false)
      "TAKE" -> cmd_give_take(state, true)
      "END" -> cmd_end(state)
      "ENDGAME" -> cmd_endgame(state)
      "IDLE" -> cmd_idle(state)
      "RESTART" -> cmd_restart(state)
      "ZAP" -> cmd_zap(state)
      "RESTORE" -> cmd_restore(state)
      "LOCK" -> cmd_lock(state, 1)
      "UNLOCK" -> cmd_lock(state, 0)
      "SEND" -> cmd_send(state)
      "BECOME" -> cmd_become(state)
      "PUT" -> cmd_put(state)
      "CHANGE" -> cmd_change(state)
      "PLAY" -> cmd_play(state)
      "CYCLE" -> cmd_cycle(state)
      "CHAR" -> cmd_char(state)
      "DIE" -> cmd_die(state)
      "BIND" -> cmd_bind(state)
      _ -> cmd_fallback(state, word)
    end
  end

  # ---- Individual commands ----------------------------------------------

  defp cmd_go(state) do
    case read_direction(state) do
      {:ok, 0, 0, state} ->
        %{state | stop_running: true}

      {:ok, dx, dy, state} ->
        state = try_move(state, dx, dy)
        repeat? = not state.moved
        state = Map.delete(state, :moved)
        %{state | stop_running: true, repeat_ins_next_tick: repeat?}

      {:error, state} ->
        %{state | stop_running: true}
    end
  end

  defp cmd_try(state) do
    case read_direction(state) do
      {:ok, 0, 0, state} ->
        %{state | stop_running: true}

      {:ok, dx, dy, state} ->
        state = try_move(state, dx, dy)

        if state.moved do
          %{Map.delete(state, :moved) | stop_running: true}
        else
          # Fall through to the next command on the line.
          read_command(Map.delete(state, :moved))
        end

      {:error, state} ->
        state
    end
  end

  defp cmd_walk(state) do
    case read_direction(state) do
      {:ok, dx, dy, state} ->
        stat = current_stat(state)
        update_stat(state, %{stat | step_x: dx, step_y: dy})

      {:error, state} ->
        state
    end
  end

  defp cmd_set(state) do
    {flag, state} = read_word(state)
    %{state | game: Game.set_flag(state.game, flag)}
  end

  defp cmd_clear(state) do
    {flag, state} = read_word(state)
    %{state | game: Game.clear_flag(state.game, flag)}
  end

  defp cmd_if(state) do
    {word, state} = read_word(state)
    {truthy?, state} = check_condition(word, state)
    if truthy?, do: read_command(state), else: state
  end

  defp cmd_shoot(state, element) do
    case read_direction(state) do
      {:ok, dx, dy, state} ->
        stat = current_stat(state)
        {game, _} = Game.board_shoot(state.game, stat.x, stat.y, dx, dy, 1, element)
        %{state | game: game, stop_running: true}

      {:error, state} ->
        %{state | stop_running: true}
    end
  end

  defp cmd_give_take(state, subtract?) do
    {counter_word, state} = read_word(state)
    {value, state} = read_value(state)

    case counter_key(counter_word) do
      nil ->
        state

      key ->
        delta = if subtract?, do: -value, else: value
        current = player_counter(state.game, key)

        cond do
          value <= 0 ->
            state

          current + delta >= 0 ->
            %{state | game: set_player_counter(state.game, key, current + delta)}

          true ->
            # Not enough to take → retry remainder of line as further commands.
            read_command(state)
        end
    end
  end

  defp cmd_end(state), do: %{state | end_of_program: true, last_char: 0}

  defp cmd_endgame(state) do
    game = %{state.game | player: %{state.game.player | health: 0}}
    %{state | game: game}
  end

  defp cmd_idle(state), do: %{state | stop_running: true}

  defp cmd_restart(state), do: %{state | position: 0, line_finished: false}

  defp cmd_zap(state) do
    {label, state} = read_word(state)
    refresh_code(%{state | game: zap_label(state.game, state.stat_idx, label)})
  end

  defp cmd_restore(state) do
    {label, state} = read_word(state)
    refresh_code(%{state | game: restore_label(state.game, state.stat_idx, label)})
  end

  defp refresh_code(state) do
    code = Enum.at(state.game.stats, state.stat_idx).code
    %{state | code: code, code_size: byte_size(code)}
  end

  defp cmd_lock(state, value) do
    stat = current_stat(state)
    update_stat(state, %{stat | p2: value})
  end

  defp cmd_send(state) do
    {target, state} = read_word(state)
    {game, sent_to_self?} = do_send(state.game, state.stat_idx, target, false)
    state = %{state | game: game}

    # If self jumped, position was rewritten on our stat — pick it up
    # and keep parsing from there (don't skip the rest of this line).
    if sent_to_self? do
      stat = current_stat(state)
      %{state | position: stat.instruction, line_finished: false}
    else
      state
    end
  end

  defp cmd_become(state) do
    case parse_tile(state) do
      {:ok, tile, state} ->
        %{state | replace_stat: true, replace_tile: tile}

      {:error, state} ->
        state
    end
  end

  defp cmd_put(state) do
    case read_direction(state) do
      {:ok, 0, 0, state} ->
        state

      {:ok, dx, dy, state} ->
        case parse_tile(state) do
          {:ok, {elem, color}, state} ->
            stat = current_stat(state)
            tx = stat.x + dx
            ty = stat.y + dy

            if in_bounds?(tx, ty) do
              game = state.game

              game =
                if walkable?(game, tx, ty), do: game, else: Game.push_tile(game, tx, ty, dx, dy)

              game = place_tile(game, tx, ty, elem, color)
              %{state | game: game}
            else
              state
            end

          {:error, state} ->
            state
        end

      {:error, state} ->
        state
    end
  end

  defp cmd_change(state) do
    with {:ok, from_tile, state} <- parse_tile(state),
         {:ok, to_tile, state} <- parse_tile(state) do
      game = change_tiles(state.game, from_tile, to_tile)
      %{state | game: game}
    else
      {:error, state} -> state
    end
  end

  # #play: consume the rest of the line. Sound is out of scope for now.
  defp cmd_play(state) do
    state = skip_line(state)
    %{state | line_finished: false}
  end

  defp cmd_cycle(state) do
    {value, state} = read_value(state)

    if value > 0 do
      stat = current_stat(state)
      update_stat(state, %{stat | cycle: value})
    else
      state
    end
  end

  defp cmd_char(state) do
    {value, state} = read_value(state)

    if value > 0 and value <= 255 do
      stat = current_stat(state)
      update_stat(state, %{stat | p1: value})
    else
      state
    end
  end

  defp cmd_die(state) do
    %{state | replace_stat: true, replace_tile: {0, 0x0F}}
  end

  defp cmd_bind(state) do
    {target, state} = read_word(state)

    case find_object_by_name(state.game, state.stat_idx, target) do
      nil ->
        state

      other_idx ->
        other = Enum.at(state.game.stats, other_idx)
        stat = current_stat(state)
        state = update_stat(state, %{stat | code: other.code})
        %{state | position: 0, code: other.code, code_size: byte_size(other.code)}
    end
  end

  # Unknown word: try sending to self (bare label send). If not found
  # and the word doesn't contain `:` (pure garbage), silently ignore.
  defp cmd_fallback(state, word) do
    {game, sent_to_self?} = do_send(state.game, state.stat_idx, word, false)
    state = %{state | game: game}

    if sent_to_self? do
      stat = current_stat(state)
      %{state | position: stat.instruction, line_finished: false}
    else
      state
    end
  end

  # ---- Finalization ------------------------------------------------------

  defp finalize(state) do
    position =
      cond do
        state.end_of_program -> -1
        state.repeat_ins_next_tick -> state.last_position
        true -> state.position
      end

    game = save_position(state.game, state.stat_idx, position)

    state = %{state | game: game}
    state = maybe_show_text(state)
    state = maybe_replace_stat(state)
    state.game
  end

  defp save_position(game, stat_idx, position) do
    stat = Enum.at(game.stats, stat_idx)
    %{game | stats: List.replace_at(game.stats, stat_idx, %Stat{stat | instruction: position})}
  end

  defp maybe_show_text(%{text_lines: []} = state), do: state

  defp maybe_show_text(state) do
    lines = Enum.reverse(state.text_lines)
    title = object_name(state.game, state.stat_idx) || "Interaction"

    game = %{state.game | pending_scroll: %{title: title, lines: lines, line_pos: 1}}
    %{state | game: game}
  end

  defp maybe_replace_stat(%{replace_stat: false} = state), do: state

  defp maybe_replace_stat(state) do
    stat = Enum.at(state.game.stats, state.stat_idx)
    {elem, color} = state.replace_tile
    game = Game.remove_stat(state.game, state.stat_idx)
    game = place_tile(game, stat.x, stat.y, elem, color)
    %{state | game: game}
  end

  # ---- Low-level char/word readers --------------------------------------

  defp read_char(state) do
    if state.position >= state.code_size do
      {0, state}
    else
      byte = :binary.at(state.code, state.position)
      {byte, %{state | position: state.position + 1}}
    end
  end

  defp read_word(state) do
    {ch, state} = skip_spaces(state)
    upper = up_char(ch)

    if upper >= ?0 and upper <= ?9 do
      # Number — don't consume, back up so read_value can grab it.
      {"", back_up(state)}
    else
      collect_word([], upper, state)
    end
  end

  defp collect_word(acc, ch, state) do
    if word_char?(ch) do
      {next, state} = read_char(state)
      collect_word([ch | acc], up_char(next), state)
    else
      # The stop char hasn't been consumed (it was read but doesn't
      # belong to the word); back up so the outer loop sees it.
      state = back_up(state)
      {acc |> Enum.reverse() |> List.to_string(), state}
    end
  end

  defp word_char?(ch) do
    (ch >= ?A and ch <= ?Z) or (ch >= ?0 and ch <= ?9) or ch == ?: or ch == ?_
  end

  defp skip_spaces(state) do
    {ch, state} = read_char(state)
    if ch == ?\s, do: skip_spaces(state), else: {ch, state}
  end

  defp back_up(%{position: 0} = state), do: state
  defp back_up(state), do: %{state | position: state.position - 1}

  defp up_char(ch) when ch in ?a..?z, do: ch - 32
  defp up_char(ch), do: ch

  defp read_value(state) do
    {ch, state} = skip_spaces(state)
    upper = up_char(ch)

    if upper >= ?0 and upper <= ?9 do
      collect_digits([ch], state)
    else
      # No digits → return -1, back up one so the caller sees the char.
      {-1, back_up(state)}
    end
  end

  defp collect_digits(acc, state) do
    {ch, state} = read_char(state)

    if ch >= ?0 and ch <= ?9 do
      collect_digits([ch | acc], state)
    else
      state = back_up(state)
      value = acc |> Enum.reverse() |> List.to_string() |> String.to_integer()
      {value, state}
    end
  end

  defp read_line_to_end(state), do: read_line_to_end([], state)

  defp read_line_to_end(acc, state) do
    {ch, state} = read_char(state)

    cond do
      ch == 0 -> {acc |> Enum.reverse() |> :binary.list_to_bin(), state}
      ch == 13 -> {acc |> Enum.reverse() |> :binary.list_to_bin(), state}
      true -> read_line_to_end([ch | acc], state)
    end
  end

  defp skip_line(state) do
    {ch, state} = read_char(state)

    cond do
      ch == 0 -> state
      ch == 13 -> state
      true -> skip_line(state)
    end
  end

  # ---- Directions --------------------------------------------------------

  defp read_direction(state) do
    {word, state} = read_word(state)
    parse_direction(word, state)
  end

  defp parse_direction(word, state) do
    case word do
      w when w in ["N", "NORTH"] -> {:ok, 0, -1, state}
      w when w in ["S", "SOUTH"] -> {:ok, 0, 1, state}
      w when w in ["E", "EAST"] -> {:ok, 1, 0, state}
      w when w in ["W", "WEST"] -> {:ok, -1, 0, state}
      w when w in ["I", "IDLE"] -> {:ok, 0, 0, state}
      "SEEK" -> seek_direction(state)
      "FLOW" -> flow_direction(state)
      "RND" -> rnd_direction(state)
      "RNDNS" -> {:ok, 0, Enum.random([-1, 1]), state}
      "RNDNE" -> rndne_direction(state)
      "CW" -> modify_direction(state, &rotate_cw/2)
      "CCW" -> modify_direction(state, &rotate_ccw/2)
      "OPP" -> modify_direction(state, &opposite/2)
      "RNDP" -> modify_direction(state, &rndp/2)
      _ -> {:error, state}
    end
  end

  defp seek_direction(state) do
    stat = current_stat(state)
    {dx, dy} = Directions.seek(state.game, stat)
    {:ok, dx, dy, state}
  end

  defp flow_direction(state) do
    stat = current_stat(state)
    {:ok, stat.step_x, stat.step_y, state}
  end

  defp rnd_direction(state) do
    {dx, dy} = Directions.random_step()
    {:ok, dx, dy, state}
  end

  defp rndne_direction(state) do
    dx = Enum.random([0, 1])
    dy = if dx == 0, do: -1, else: 0
    {:ok, dx, dy, state}
  end

  defp modify_direction(state, fun) do
    case read_direction(state) do
      {:ok, dx, dy, state} ->
        {nx, ny} = fun.(dx, dy)
        {:ok, nx, ny, state}

      {:error, state} ->
        {:error, state}
    end
  end

  defp rotate_cw(dx, dy), do: {-dy, dx}
  defp rotate_ccw(dx, dy), do: {dy, -dx}
  defp opposite(dx, dy), do: {-dx, -dy}

  defp rndp(dx, dy) do
    if Enum.random([0, 1]) == 0, do: {-dy, dx}, else: {dy, -dx}
  end

  # ---- Conditions --------------------------------------------------------

  defp check_condition(word, state) do
    case word do
      "NOT" ->
        {next, state} = read_word(state)
        {result, state} = check_condition(next, state)
        {not result, state}

      "ALLIGNED" ->
        stat = current_stat(state)
        player = Enum.at(state.game.stats, 0)
        {stat.x == player.x or stat.y == player.y, state}

      "CONTACT" ->
        stat = current_stat(state)
        player = Enum.at(state.game.stats, 0)
        d = (stat.x - player.x) * (stat.x - player.x) + (stat.y - player.y) * (stat.y - player.y)
        {d == 1, state}

      "BLOCKED" ->
        case read_direction(state) do
          {:ok, dx, dy, state} ->
            stat = current_stat(state)
            {not walkable?(state.game, stat.x + dx, stat.y + dy), state}

          {:error, state} ->
            {false, state}
        end

      "ENERGIZED" ->
        {Game.energized?(state.game), state}

      "ANY" ->
        case parse_tile(state) do
          {:ok, tile, state} -> {find_tile_on_board(state.game, tile), state}
          {:error, state} -> {false, state}
        end

      flag ->
        {Game.flag?(state.game, flag), state}
    end
  end

  # ---- Tile parsing ------------------------------------------------------

  # `<color?> <element>` where color is one of BLUE/GREEN/CYAN/RED/PURPLE/
  # YELLOW/WHITE, and element is matched by `Element.name/1`. Color is
  # optional; color 0 means "use whatever is currently there".
  @colors %{
    "BLUE" => 0x09,
    "GREEN" => 0x0A,
    "CYAN" => 0x0B,
    "RED" => 0x0C,
    "PURPLE" => 0x0D,
    "YELLOW" => 0x0E,
    "WHITE" => 0x0F
  }

  defp parse_tile(state) do
    {word, state} = read_word(state)

    {color, word, state} =
      case Map.get(@colors, word) do
        nil ->
          {0, word, state}

        c ->
          {next_word, next_state} = read_word(state)
          {c, next_word, next_state}
      end

    case element_by_name(word) do
      nil -> {:error, state}
      id -> {:ok, {id, color}, state}
    end
  end

  defp element_by_name(word_upper) do
    Enum.find_value(0..53, fn id ->
      name = Element.name(id) |> Atom.to_string() |> String.upcase() |> strip_non_alnum()
      if name == word_upper, do: id
    end)
  end

  defp strip_non_alnum(s) do
    for <<c <- s>>, c in ?A..?Z or c in ?0..?9, into: "", do: <<c>>
  end

  defp find_tile_on_board(game, {element, color}) do
    Enum.any?(game.tiles, fn
      {_, {^element, c}} -> color == 0 or color_match?(c, color)
      _ -> false
    end)
  end

  defp color_match?(tile_color, wanted), do: rem(tile_color, 16) == rem(wanted, 16)

  defp place_tile(game, x, y, element, color) do
    case Game.tile_at(game, x, y) do
      {@player, _} ->
        game

      {existing, existing_color} ->
        color = if color == 0, do: existing_color, else: color

        game =
          case find_stat_at(game.stats, x, y) do
            nil -> game
            idx -> Game.remove_stat(game, idx)
          end

        if existing == element do
          %{game | tiles: Map.put(game.tiles, {x, y}, {element, color})}
        else
          %{game | tiles: Map.put(game.tiles, {x, y}, {element, color})}
        end

      nil ->
        game
    end
  end

  defp change_tiles(game, {from_elem, from_color}, {to_elem, to_color}) do
    game.tiles
    |> Enum.reduce(game, fn
      {{x, y}, {^from_elem, c}}, acc ->
        if from_color == 0 or color_match?(c, from_color) do
          place_tile(acc, x, y, to_elem, to_color)
        else
          acc
        end

      _, acc ->
        acc
    end)
  end

  # ---- Label scanning / send --------------------------------------------

  # Returns `{game, sent_to_self?}`. `stat_id < 0` means engine-triggered
  # (respect the target's own lock for self-directed labels).
  defp do_send(game, stat_id, label, ignore_lock?) do
    {caller_id, respect_self_lock?} =
      if stat_id < 0, do: {-stat_id, true}, else: {stat_id, false}

    {target_lookup, msg} = split_target(label)

    targets =
      case target_lookup do
        nil -> if caller_id >= 0, do: [caller_id], else: []
        lookup -> resolve_targets(game, caller_id, lookup)
      end

    Enum.reduce(targets, {game, false}, fn idx, {g, sent?} ->
      case find_label_position(g, idx, msg) do
        nil ->
          {g, sent?}

        new_pos ->
          stat = Enum.at(g.stats, idx)

          if stat.p2 == 0 or ignore_lock? or (idx == caller_id and not respect_self_lock?) do
            g = save_position(g, idx, new_pos)
            {g, sent? or idx == caller_id}
          else
            {g, sent?}
          end
      end
    end)
  end

  defp split_target(label) do
    case String.split(label, ":", parts: 2) do
      [msg] -> {nil, msg}
      ["", msg] -> {nil, msg}
      [name, msg] -> {name, msg}
    end
  end

  defp resolve_targets(game, _caller_id, "ALL") do
    for {_stat, idx} <- Enum.with_index(game.stats), idx > 0, do: idx
  end

  defp resolve_targets(game, caller_id, "OTHERS") do
    for {_stat, idx} <- Enum.with_index(game.stats),
        idx > 0 and idx != caller_id,
        do: idx
  end

  defp resolve_targets(_game, caller_id, "SELF"), do: [caller_id]

  defp resolve_targets(game, _caller_id, name) do
    for {_stat, idx} <- Enum.with_index(game.stats),
        idx > 0 and object_name(game, idx) == name,
        do: idx
  end

  # For RESTART the position is just 0. For any other label, scan for
  # `\r:label\r` (or `\r:label\0`/EOF).
  defp find_label_position(_game, _stat_idx, "RESTART"), do: 0

  defp find_label_position(game, stat_idx, label) do
    stat = Enum.at(game.stats, stat_idx)
    scan_label(stat.code, 0, String.upcase(label), ?:)
  end

  defp scan_label(code, pos, label_upper, prefix_char) when pos < byte_size(code) do
    # Labels start at position 0 or right after a CR, and begin with
    # `prefix_char` (`:` for normal, `'` for zapped).
    starts_here? = pos == 0 or :binary.at(code, pos - 1) == 13

    if starts_here? and :binary.at(code, pos) == prefix_char do
      case read_label_word(code, pos + 1) do
        {word, next_pos} ->
          if String.upcase(word) == label_upper do
            # Return position past the CR that terminates this line,
            # or EOF position. That's where execution resumes.
            skip_to_line_end(code, next_pos)
          else
            scan_label(code, pos + 1, label_upper, prefix_char)
          end
      end
    else
      scan_label(code, pos + 1, label_upper, prefix_char)
    end
  end

  defp scan_label(_code, _pos, _label_upper, _prefix_char), do: nil

  defp read_label_word(code, pos) do
    read_label_word(code, pos, [])
  end

  defp read_label_word(code, pos, acc) when pos < byte_size(code) do
    byte = :binary.at(code, pos)

    if word_char?(up_char(byte)) and byte != ?: do
      read_label_word(code, pos + 1, [byte | acc])
    else
      {acc |> Enum.reverse() |> :binary.list_to_bin(), pos}
    end
  end

  defp read_label_word(_code, pos, acc) do
    {acc |> Enum.reverse() |> :binary.list_to_bin(), pos}
  end

  defp skip_to_line_end(code, pos) when pos < byte_size(code) do
    case :binary.at(code, pos) do
      0 -> pos
      13 -> pos + 1
      _ -> skip_to_line_end(code, pos + 1)
    end
  end

  defp skip_to_line_end(_code, pos), do: pos

  # Zap `:label` → `'label`, restore the opposite direction. Mutates the
  # in-memory code binary (allowed because we own it on the stat).
  defp zap_label(game, stat_idx, label) do
    rewrite_label(game, stat_idx, label, ?:, ?')
  end

  defp restore_label(game, stat_idx, label) do
    rewrite_label(game, stat_idx, label, ?', ?:)
  end

  defp rewrite_label(game, stat_idx, label, from_char, to_char) do
    stat = Enum.at(game.stats, stat_idx)
    label_upper = String.upcase(label)

    case first_label_offset(stat.code, label_upper, from_char) do
      nil ->
        game

      offset ->
        new_code = rewrite_byte(stat.code, offset, to_char)
        %{game | stats: List.replace_at(game.stats, stat_idx, %Stat{stat | code: new_code})}
    end
  end

  defp first_label_offset(code, label_upper, prefix_char) do
    first_label_offset(code, 0, label_upper, prefix_char)
  end

  defp first_label_offset(code, pos, label_upper, prefix_char) when pos < byte_size(code) do
    starts_here? = pos == 0 or :binary.at(code, pos - 1) == 13

    if starts_here? and :binary.at(code, pos) == prefix_char do
      {word, _} = read_label_word(code, pos + 1)

      if String.upcase(word) == label_upper do
        pos
      else
        first_label_offset(code, pos + 1, label_upper, prefix_char)
      end
    else
      first_label_offset(code, pos + 1, label_upper, prefix_char)
    end
  end

  defp first_label_offset(_code, _pos, _label_upper, _prefix_char), do: nil

  defp rewrite_byte(code, offset, byte) do
    <<head::binary-size(offset), _::binary-size(1), tail::binary>> = code
    <<head::binary, byte, tail::binary>>
  end

  # ---- Object discovery --------------------------------------------------

  defp find_object_by_name(game, self_idx, name) do
    game.stats
    |> Enum.with_index()
    |> Enum.find_value(fn {s, idx} ->
      if idx != self_idx and object_stat_name(s) == name, do: idx
    end)
  end

  defp object_stat_name(%Stat{code: code}) do
    case code do
      <<?@, rest::binary>> ->
        rest
        |> :binary.split(<<13>>)
        |> hd()
        |> String.upcase()
        |> String.trim()

      _ ->
        nil
    end
  end

  defp object_name(game, stat_idx) do
    stat = Enum.at(game.stats, stat_idx)

    case object_stat_name(stat) do
      nil -> nil
      "" -> nil
      name -> name
    end
  end

  # ---- Player counter accessors -----------------------------------------

  @counters %{
    "HEALTH" => :health,
    "AMMO" => :ammo,
    "GEMS" => :gems,
    "TORCHES" => :torches,
    "SCORE" => :score
  }

  defp counter_key(word), do: Map.get(@counters, word)

  defp player_counter(game, key), do: Map.get(game.player, key)

  defp set_player_counter(game, key, value) do
    %{game | player: Map.put(game.player, key, value)}
  end

  # ---- Stat helpers -----------------------------------------------------

  defp current_stat(state), do: Enum.at(state.game.stats, state.stat_idx)

  defp update_stat(state, stat) do
    game = %{state.game | stats: List.replace_at(state.game.stats, state.stat_idx, stat)}
    %{state | game: game}
  end

  defp walkable?(game, x, y) do
    case Game.tile_at(game, x, y) do
      nil -> false
      {elem, _} -> Element.walkable?(elem)
    end
  end

  defp in_bounds?(x, y), do: x in 1..60 and y in 1..25

  defp find_stat_at(stats, x, y) do
    Enum.find_index(stats, fn s -> s.x == x and s.y == y end)
  end
end
