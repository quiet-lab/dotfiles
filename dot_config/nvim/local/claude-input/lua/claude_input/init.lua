-- Буфер ввода Claude Code: содержимое буфера neovim повторяется в строке ввода
-- Claude Code через сокет herdr (pane.send_text); `:w` отправляет запрос.
-- Таймеров нет: всё по событиям сокета (docs/decisions/0007-no-timers.md).
local M = {}

local uv = vim.uv or vim.loop

-- Очистка строки ввода Claude Code: i, Ctrl+U, Esc (кодировка kitty), ggdG, i, Backspace.
M.PREFIX = "i\21\27[27uggdGi\127"
M.RAW_LIMIT = 700
local PASTE_BEGIN = "\27[200~"
local PASTE_END = "\27[201~"
local BUF_NAME = "claude://input"

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
}

-- Текст запроса: сырой, если короткий и без управляющих символов, иначе в рамке bracketed paste.
function M.payload(lines)
  local text = table.concat(lines, "\n")
  if text == "" then
    return ""
  end
  local raw = vim.fn.strchars(text) <= M.RAW_LIMIT and not text:find("[%z\1-\9\11-\31\127]")
  if raw then
    return text
  end
  return PASTE_BEGIN .. text .. PASTE_END
end

function M.request_text(lines, submit)
  return M.PREFIX .. M.payload(lines) .. (submit and "\r" or "")
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
      report_error(err)
    end
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
    request("pane.send_text", { pane_id = pane, text = M.request_text(buf_lines(), false) }, function(_, serr)
      if serr then
        state.in_flight = false
        return report_error(serr)
      end
      state.error_shown = false
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
    request("pane.send_text", { pane_id = pane, text = M.request_text(buf_lines(), true) }, function(_, serr)
      if serr then
        state.in_flight = false
        return report_error(serr)
      end
      state.error_shown = false
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
        vim.bo[buf].modified = false
      end
      state.dirty = false
      chain_done()
    end)
  end)
end

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
    end,
  })
  vim.api.nvim_set_current_buf(buf)
  vim.cmd("startinsert")
end

function M.setup()
  vim.api.nvim_create_user_command("ClaudeInput", open, { desc = "Буфер ввода Claude Code" })
end

return M
