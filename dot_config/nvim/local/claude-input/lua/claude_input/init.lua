-- Буфер ввода Claude Code: содержимое буфера neovim повторяется в строке ввода
-- Claude Code через сокет herdr (pane.send_text); `:w` отправляет запрос.
-- Таймеров нет: всё по событиям сокета (docs/decisions/0007-no-timers.md).
local M = {}

local uv = vim.uv or vim.loop
local dialog = require("claude_input.dialog")

-- Очистка строки ввода Claude Code: i, Ctrl+U, Esc (кодировка kitty), ggdG, i, Backspace.
M.PREFIX = "i\21\27[27uggdGi\127"
M.RAW_LIMIT = 700
local PASTE_BEGIN = "\27[200~"
local PASTE_END = "\27[201~"
local BUF_NAME = "claude://input"
local DIALOG_NAME = "claude://dialog"

local state = {
  buf = nil,
  in_flight = false,
  dirty = false,
  waiting = false,
  sub = nil,
  pending_submit = false,
  error_shown = false,
  warned_pane = false,
  seq = 0,
  -- Сразу после успешного `:w` строка ввода Claude Code пуста.
  just_submitted = false,
  -- Буфер диалога (design.md изменения claude-dialog-buffer, E2–E6).
  dbuf = nil,
  mode = "input",
  watch = nil,
  watch_events = 0,
  d_busy = false,
  d_refresh = false,
  d_edit = false,
  d_write = false,
  -- Текст, переданный плагином в поле свободного ввода текущего вопроса.
  field_text = "",
  -- Буфер диалога был пуст после последней передачи текста в поле.
  seen_empty = true,
  -- Подпись экрана до отправки стрелок или Enter: пока экран с ней совпадает,
  -- Claude Code ещё не обработал клавиши, и решения по нему не принимаются.
  guard = nil,
}

-- Текст запроса: сырой, если короткий и без управляющих символов, иначе в рамке bracketed paste.
function M.payload(lines)
  local text = table.concat(lines, "\n")
  if text == "" then
    return ""
  end
  -- Порог в единицах UTF-16, как длина строки JS в Claude Code.
  local units = vim.str_utfindex(text, "utf-16")
  local raw = units <= M.RAW_LIMIT and not text:find("[%z\1-\9\11-\31\127]")
  if raw then
    return text
  end
  return PASTE_BEGIN .. text .. PASTE_END
end

function M.request_text(lines)
  return M.PREFIX .. M.payload(lines)
end

local function socket_path()
  local p = vim.env.HERDR_SOCKET_PATH
  if p and p ~= "" then
    return p
  end
  return vim.fn.expand("~/.config/herdr/herdr.sock")
end

-- Разбор строки ответа: на выходе таблица или nil.
local function decode(line)
  local ok, res = pcall(vim.json.decode, line)
  if ok and type(res) == "table" then
    return res
  end
end

-- Запрос к сокету: cb(response|nil, err) вызывается в основном цикле neovim.
-- Для подписки on_line получает каждую следующую строку; возвращается закрытие соединения.
local function request(method, params, cb, on_line)
  state.seq = state.seq + 1
  local pipe = uv.new_pipe(false)
  local buf = ""
  local first = true
  local closed = false
  local function close()
    if not closed then
      closed = true
      pipe:read_stop()
      if not pipe:is_closing() then
        pipe:close()
      end
    end
  end
  local function finish(res, err)
    if first then
      first = false
      vim.schedule(function()
        cb(res, err)
      end)
    end
  end
  pipe:connect(socket_path(), function(cerr)
    if cerr then
      close()
      return finish(nil, cerr)
    end
    local line = vim.json.encode({ id = "ci" .. state.seq, method = method, params = params }) .. "\n"
    pipe:write(line, function(werr)
      if werr then
        close()
        finish(nil, werr)
      end
    end)
    pipe:read_start(function(rerr, data)
      if rerr then
        close()
        return finish(nil, rerr)
      end
      if data == nil then
        close()
        if first then
          finish(nil, "соединение закрыто без ответа")
        elseif on_line then
          vim.schedule(function()
            on_line(nil)
          end)
        end
        return
      end
      buf = buf .. data
      while true do
        local nl = buf:find("\n", 1, true)
        if not nl then
          break
        end
        local l = buf:sub(1, nl - 1)
        buf = buf:sub(nl + 1)
        if l ~= "" then
          local res = decode(l)
          if first then
            if on_line == nil then
              close()
            end
            if res and res.error then
              finish(nil, res.error.message or "ошибка herdr")
            elseif res then
              finish(res)
            else
              finish(nil, "ответ не разобран")
            end
          elseif on_line then
            vim.schedule(function()
              on_line(res)
            end)
          end
        end
      end
    end)
  end)
  return close
end
M._request = request

-- Текст сырыми байтами, затем Enter клавишей: сырой `\r` строка ввода
-- Claude Code 2.1.319 запросом не считает, а клавишу herdr кодирует по режиму
-- клавиатуры терминала. Порядок байтов сохраняется: запросы идут друг за другом.
local function send_then_enter(pane, text, enter, cb)
  local function press()
    if not enter then
      return cb()
    end
    request("pane.send_keys", { pane_id = pane, keys = { "enter" } }, function(_, err)
      cb(err)
    end)
  end
  if text == "" then
    return press()
  end
  request("pane.send_text", { pane_id = pane, text = text }, function(_, err)
    if err then
      return cb(err)
    end
    press()
  end)
end

local function pane_id()
  local p = vim.env.CLAUDE_INPUT_PANE
  if p and p ~= "" then
    return p
  end
end

local function buf_lines()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  end
  return {}
end

-- cb(status|nil, err)
local function get_status(pane, cb)
  request("pane.get", { pane_id = pane }, function(res, err)
    if err or not res then
      return cb(nil, err or "нет ответа")
    end
    local p = res.result and res.result.pane
    cb(p and p.agent_status or "unknown")
  end)
end
M._get_status = get_status

local function report_error(err)
  if not state.error_shown then
    state.error_shown = true
    vim.notify("claude-input: сокет herdr: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local schedule_send

-- Конец цепочки: если за время её работы буфер менялся, начинается новая.
local function chain_done()
  state.in_flight = false
  if state.pending_submit then
    state.pending_submit = false
    M.submit()
  elseif state.dirty and not state.waiting then
    state.dirty = false
    schedule_send()
  end
end

local function open_subscription(pane)
  state.waiting = true
  local close
  close = request("events.subscribe", {
    subscriptions = { { type = "pane.agent_status_changed", pane_id = pane } },
  }, function(_, err)
    if err then
      state.waiting = false
      state.sub = nil
      if close then
        close()
      end
      return report_error(err)
    end
    -- Статус мог покинуть blocked до установки подписки.
    get_status(pane, function(status)
      if not state.waiting or state.sub ~= close or not status or status == "blocked" then
        return
      end
      close()
      state.sub = nil
      state.waiting = false
      if state.dirty then
        state.dirty = false
        schedule_send()
      end
    end)
  end, function(ev)
    if not state.waiting then
      return
    end
    if ev == nil then
      state.waiting = false
      state.sub = nil
      return
    end
    local data = ev.data
    local status = type(data) == "table" and data.agent_status or nil
    if ev.event == "pane.agent_status_changed" and status and status ~= "blocked" then
      if state.sub then
        state.sub()
      end
      state.sub = nil
      state.waiting = false
      if state.dirty then
        state.dirty = false
        schedule_send()
      end
    end
  end)
  state.sub = close
end

schedule_send = function()
  local pane = pane_id()
  if not pane then
    return
  end
  if state.in_flight or state.waiting then
    state.dirty = true
    return
  end
  -- После `:w` строка ввода уже пуста: лишний Esc очистки закрыл бы открытый
  -- запросом диалог Claude Code (например, /help).
  if state.just_submitted and M.payload(buf_lines()) == "" then
    return
  end
  state.in_flight = true
  get_status(pane, function(status, err)
    if err then
      state.in_flight = false
      state.pending_submit = false
      return report_error(err)
    end
    if state.pending_submit then
      state.in_flight = false
      state.pending_submit = false
      return M.submit()
    end
    if status == "blocked" then
      state.in_flight = false
      state.dirty = true
      if not state.waiting then
        open_subscription(pane)
      end
      return
    end
    local payload = M.payload(buf_lines())
    request("pane.send_text", { pane_id = pane, text = M.PREFIX .. payload }, function(_, serr)
      if serr then
        state.in_flight = false
        return report_error(serr)
      end
      state.error_shown = false
      state.just_submitted = false
      chain_done()
    end)
  end)
end
M.schedule_send = schedule_send

-- Отправка запроса (`:w`).
function M.submit()
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = buf_lines()
  local empty = true
  for _, l in ipairs(lines) do
    if l ~= "" then
      empty = false
      break
    end
  end
  if empty then
    vim.bo[buf].modified = false
    return
  end
  local pane = pane_id()
  if not pane then
    return
  end
  if state.in_flight then
    state.pending_submit = true
    return
  end
  state.in_flight = true
  get_status(pane, function(status, err)
    if err then
      state.in_flight = false
      return report_error(err)
    end
    if status == "blocked" then
      state.in_flight = false
      vim.notify("Claude Code ждёт ответа в диалоге", vim.log.levels.WARN)
      return
    end
    send_then_enter(pane, M.request_text(buf_lines()), true, function(serr)
      if serr then
        state.in_flight = false
        return report_error(serr)
      end
      state.error_shown = false
      state.just_submitted = true
      if state.waiting then
        if state.sub then
          state.sub()
        end
        state.sub = nil
        state.waiting = false
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
        vim.bo[buf].modified = false
      end
      state.dirty = false
      chain_done()
    end)
  end)
end

-- Экран панели Claude Code: cb(text|nil, err).
local function read_screen(pane, cb)
  request("pane.read", { pane_id = pane, source = "detection" }, function(res, err)
    if err or not res then
      return cb(nil, err or "нет ответа")
    end
    local r = res.result and res.result.read
    cb(r and r.text or "")
  end)
end

local function set_lines_clean(buf, lines)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
  end
end

-- Окно, показывающее буфер from, переводится на буфер to.
local function swap_window(from, to)
  local wins = vim.fn.win_findbuf(from)
  local win = wins[1] or vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, to)
end

local d_step

local function ensure_dialog_buf()
  if state.dbuf and vim.api.nvim_buf_is_valid(state.dbuf) then
    return state.dbuf
  end
  local buf = vim.api.nvim_create_buf(true, false)
  state.dbuf = buf
  vim.api.nvim_buf_set_name(buf, DIALOG_NAME)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  local group = vim.api.nvim_create_augroup("claude_input_dialog", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = buf,
    callback = function()
      M.dialog_changed()
    end,
  })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
      state.d_write = true
      d_step()
    end,
  })
  return buf
end

-- Правка буфера диалога.
function M.dialog_changed()
  local buf = state.dbuf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") == "" then
    state.seen_empty = true
  end
  state.d_edit = true
  d_step()
end

local function show_dialog()
  local dbuf = ensure_dialog_buf()
  set_lines_clean(dbuf, {})
  state.guard = nil
  state.field_text = ""
  state.seen_empty = true
  state.mode = "dialog"
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    swap_window(state.buf, dbuf)
  end
  vim.cmd("startinsert")
end

local function show_input()
  state.mode = "input"
  state.guard = nil
  state.field_text = ""
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.dbuf then
    swap_window(state.dbuf, state.buf)
  end
  set_lines_clean(state.dbuf, {})
end

-- Решение по свежему экрану: job — "write", "edit" или "refresh".
-- done() завершает цепочку; send(keys) отправляет клавиши и затем завершает её.
local function d_decide(job, status, text, send, done)
  local d = text and dialog.parse(text)
  if not d or (state.mode ~= "dialog" and status ~= "blocked") then
    if state.mode == "dialog" then
      show_input()
    end
    return done()
  end
  if state.mode ~= "dialog" then
    show_dialog()
    return done()
  end
  local dbuf = state.dbuf
  local lines = vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)
  local content = table.concat(lines, "\n")
  local on_free = dialog.on_free(d)
  local sig = dialog.signature(d)
  local stale = state.guard ~= nil and state.guard == sig
  if not stale then
    state.guard = nil
  end
  if job == "write" then
    -- Enter безопасен и на прежнем экране: Claude Code обрабатывает клавиши по порядку.
    local keys = dialog.submit_keys(d)
    set_lines_clean(dbuf, {})
    state.field_text = ""
    state.seen_empty = true
    state.guard = sig
    return send(keys)
  end
  if job ~= "edit" or stale then
    -- Прежний экран: решение — при следующей правке или событии подписки.
    return done()
  end
  local n = content:match("^%s*(%d+)%s*$")
  if n and (not on_free or state.field_text == "" or state.seen_empty) then
    local dirty_field = on_free and (state.field_text ~= "" or d.free_text ~= "")
    local keys = dialog.digit_keys(d, tonumber(n), dirty_field and M.PREFIX or nil)
    set_lines_clean(dbuf, {})
    state.seen_empty = true
    if dirty_field then
      state.field_text = ""
    end
    if keys and keys ~= "" then
      state.guard = sig
      return send(keys)
    end
    return done()
  end
  if on_free then
    if content == state.field_text and content == d.free_text then
      return done()
    end
    state.field_text = content
    if content ~= "" then
      state.seen_empty = false
    end
    return send(M.PREFIX .. M.payload(lines))
  end
  return done()
end

-- Цепочка буфера диалога: статус, экран, решение, отправка; в полёте одна.
d_step = function()
  local pane = pane_id()
  if not pane or state.d_busy then
    return
  end
  -- Правка раньше записи: последний текст поля уходит до Enter.
  local job
  if state.d_edit then
    job = "edit"
    state.d_edit = false
  elseif state.d_write then
    job = "write"
    state.d_write = false
  elseif state.d_refresh then
    job = "refresh"
  else
    return
  end
  state.d_refresh = false
  state.d_busy = true
  if not state.watch then
    M.watch()
  end
  local function done()
    state.d_busy = false
    d_step()
  end
  local function fail(err)
    state.d_busy = false
    report_error(err)
  end
  get_status(pane, function(status, err)
    if err then
      return fail(err)
    end
    read_screen(pane, function(text, rerr)
      if rerr then
        return fail(rerr)
      end
      d_decide(job, status, text, function(keys)
        local enter = keys:sub(-#dialog.ENTER) == dialog.ENTER
        if enter then
          keys = keys:sub(1, -#dialog.ENTER - 1)
        end
        send_then_enter(pane, keys, enter, function(serr)
          if serr then
            return fail(serr)
          end
          state.error_shown = false
          done()
        end)
      end, done)
    end)
  end)
end

-- Постоянная подписка на смену статуса панели Claude Code (E2).
function M.watch()
  local pane = pane_id()
  if not pane or state.watch then
    return
  end
  state.watch_events = 0
  local close
  close = request("events.subscribe", {
    subscriptions = { { type = "pane.agent_status_changed", pane_id = pane } },
  }, function(_, err)
    if err then
      if state.watch == close then
        state.watch = nil
      end
      close()
      return
    end
    state.d_refresh = true
    d_step()
  end, function(ev)
    if state.watch ~= close then
      return
    end
    if ev == nil then
      state.watch = nil
      -- Обрыв после событий — подписка открывается заново один раз;
      -- обрыв без событий — следующая правка буфера диалога.
      if state.watch_events > 0 then
        M.watch()
      end
      return
    end
    if ev.event == "pane.agent_status_changed" then
      state.watch_events = state.watch_events + 1
      state.d_refresh = true
      d_step()
    end
  end)
  state.watch = close
end

M._state = state

local function open()
  if not pane_id() and not state.warned_pane then
    state.warned_pane = true
    vim.notify("claude-input: CLAUDE_INPUT_PANE не задана, трансляции нет", vim.log.levels.WARN)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_set_current_buf(state.buf)
    vim.cmd("startinsert")
    return
  end
  local buf = vim.api.nvim_create_buf(true, false)
  state.buf = buf
  vim.api.nvim_buf_set_name(buf, BUF_NAME)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "markdown"
  local group = vim.api.nvim_create_augroup("claude_input", { clear = true })
  -- Файл соответствия панелей после `:q` устарел: удаляется, если он указывает на эту панель.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      local cp, own = pane_id(), vim.env.HERDR_PANE_ID
      if not cp or not own then
        return
      end
      local dir = vim.env.XDG_STATE_HOME
      if not dir or dir == "" then
        dir = vim.fn.expand("~/.local/state")
      end
      local f = dir .. "/claude-input/" .. cp:gsub(":", "_")
      local fh = io.open(f, "r")
      if not fh then
        return
      end
      local content = (fh:read("*a") or ""):gsub("\n$", "")
      fh:close()
      if content == own then
        os.remove(f)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    buffer = buf,
    callback = function()
      schedule_send()
    end,
  })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = function()
      M.submit()
    end,
  })
  -- Содержимое уже повторено в строке ввода Claude Code, поэтому `:q` не требует записи.
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modified = false
      end
      if state.dbuf and vim.api.nvim_buf_is_valid(state.dbuf) then
        vim.bo[state.dbuf].modified = false
      end
    end,
  })
  local start = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(buf)
  -- Пустой безымянный буфер запуска не нужен: без него строка вкладок скрыта.
  if
    start ~= buf
    and vim.api.nvim_buf_get_name(start) == ""
    and vim.bo[start].buftype == ""
    and not vim.bo[start].modified
    and vim.api.nvim_buf_line_count(start) == 1
    and vim.api.nvim_buf_get_lines(start, 0, 1, false)[1] == ""
  then
    pcall(vim.api.nvim_buf_delete, start, {})
  end
  vim.cmd("startinsert")
  M.watch()
end

function M.setup()
  vim.api.nvim_create_user_command("ClaudeInput", open, { desc = "Буфер ввода Claude Code" })
end

return M
