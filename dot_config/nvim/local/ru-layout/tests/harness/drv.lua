-- Драйвер тестов: запускает `nvim --embed --headless` дочерним процессом (RPC по
-- stdio), подаёт клавиши через nvim_input (как с клавиатуры) и читает состояние
-- через nvim_exec_lua. Ожидание — по ответу RPC и событиям, без sleep и таймеров.
-- Пути считаются от местоположения файла, поэтому драйвер работает из любого каталога.
local M = {}
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
M.here = here
-- Корень плагина: два уровня вверх от tests/harness.
M.root = vim.fn.fnamemodify(here, ":h:h")
M.rows = {}
M.fails = {}
M.DEVICE = "dh747-w-corne"

-- Верхний предел vim.wait: ожидание идёт до события, зависание ловит предел прогона
-- целиком, а не срок этого вызова.
local FOREVER = 2 ^ 31 - 1

local tmp, hypr_job

-- Строка таблицы результата: опыт | ввод | ожидание | факт | вывод. ok — булево
-- (nil — сравнение expect и fact по глубокому равенству).
function M.row(exp, input, expect, fact, ok)
  if ok == nil then
    ok = vim.deep_equal(expect, fact)
  end
  local function s(v)
    return (type(v) == "string" and not v:find("[\n%c]")) and v or vim.inspect(v, { newline = " ", indent = "" })
  end
  local verdict = ok and "ok" or "FAIL"
  local r = { exp, s(input), s(expect), s(fact), verdict }
  M.rows[#M.rows + 1] = r
  if not ok then
    M.fails[#M.fails + 1] = r
  end
  io.stdout:write(("ROW | %s | %s | %s | %s | %s\n"):format(unpack(r)))
  io.stdout:flush()
  return ok
end

-- Проверка без ввода: имя, ожидание, факт.
function M.check(name, expect, fact)
  return M.row(name, "", expect, fact)
end

-- Итог набора: ALL OK и код 0 либо FAIL по каждой несовпавшей строке и код 1.
function M.finish()
  if #M.fails == 0 then
    io.stdout:write("ALL OK\n")
    io.stdout:flush()
    vim.cmd("qa!")
  else
    for _, r in ipairs(M.fails) do
      io.stdout:write(("FAIL | %s | %s | ожидалось %s | получено %s\n"):format(r[1], r[2], r[3], r[4]))
    end
    io.stdout:flush()
    vim.cmd("cquit 1")
  end
end

-- Поднять двойник Hyprland: корень $XDG_RUNTIME_DIR/hypr, подпись «test».
local function start_hypr(keymap)
  local out = {}
  hypr_job = vim.fn.jobstart({ "python3", "-I", here .. "/fake-hypr.py", tmp .. "/run/hypr", "test", keymap }, {
    on_stdout = function(_, data)
      for _, l in ipairs(data) do
        out[#out + 1] = l
      end
    end,
  })
  assert(hypr_job > 0, "двойник Hyprland не запустился")
  M.hypr_pid = vim.fn.jobpid(hypr_job)
  -- Ожидание строки «ready» от двойника: до события, не по сроку.
  vim.wait(FOREVER, function()
    return vim.tbl_contains(out, "ready")
  end, 5)
end

-- opts: { plugins = {каталоги из ~/.local/share/nvim/lazy}, langmap = bool,
--         hypr = "ru"|"us", env = {…} }
function M.start(opts)
  opts = opts or {}
  tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. "/run", "p", tonumber("700", 8))
  local env = {
    XDG_CONFIG_HOME = tmp .. "/config",
    XDG_DATA_HOME = tmp .. "/data",
    XDG_STATE_HOME = tmp .. "/state",
    XDG_CACHE_HOME = tmp .. "/cache",
    -- Всегда свой каталог: сокеты настоящего Hyprland испытуемому не видны.
    XDG_RUNTIME_DIR = tmp .. "/run",
    HYPRLAND_INSTANCE_SIGNATURE = "",
    EXP_LANGMAP = opts.langmap and "1" or "0",
    EXP_PLUGINS = table.concat(opts.plugins or {}, ","),
  }
  if opts.hypr then
    start_hypr(opts.hypr == "ru" and "Russian" or "English (US)")
    env.HYPRLAND_INSTANCE_SIGNATURE = "test"
  end
  for k, v in pairs(opts.env or {}) do
    env[k] = v
  end
  M.ch = vim.fn.jobstart(
    { "nvim", "--embed", "--headless", "--clean", "-n", "-i", "NONE", "-u", here .. "/init.lua" },
    { rpc = true, env = env }
  )
  assert(M.ch > 0, "nvim не запустился")
  M.pid = M.req("nvim_call_function", "getpid", {})
  M.req("nvim_get_api_info")
  return M.ch
end

function M.req(method, ...)
  return vim.rpcrequest(M.ch, method, ...)
end
function M.input(keys)
  return M.req("nvim_input", keys)
end
-- Выполнить Lua в испытуемом nvim; код получает аргументы через ...
function M.lua(code, ...)
  return M.req("nvim_exec_lua", code, { ... })
end
function M.mode()
  return M.req("nvim_get_mode")
end
-- «Барьер»: обычный запрос обрабатывается после разбора уже поданного ввода. Если
-- nvim ждёт аргумент команды (blocking), обычные запросы не обслуживаются, тогда
-- возвращается "BLOCKING:<режим>" без запроса.
function M.sync()
  local m = M.mode()
  if m.blocking then
    return "BLOCKING:" .. m.mode
  end
  return M.lua("return vim.fn.mode(1)")
end
function M.cursor()
  return M.lua("return vim.api.nvim_win_get_cursor(0)")
end
function M.lines()
  return M.lua("return vim.api.nvim_buf_get_lines(0,0,-1,false)")
end
function M.set_lines(lines)
  M.lua("vim.api.nvim_buf_set_lines(0,0,-1,false,...); vim.api.nvim_win_set_cursor(0,{1,0})", lines)
end

-- Запрос к .socket.sock двойника; возвращает ответ. Ожидание — по закрытию сокета.
local function hypr_request(cmd)
  local pipe = vim.uv.new_pipe(false)
  local reply, done = {}, false
  pipe:connect(tmp .. "/run/hypr/test/.socket.sock", function(err)
    assert(not err, err)
    pipe:read_start(function(rerr, chunk)
      assert(not rerr, rerr)
      if chunk then
        reply[#reply + 1] = chunk
      else
        pipe:close()
        done = true
      end
    end)
    pipe:write(cmd)
  end)
  vim.wait(FOREVER, function()
    return done
  end, 1)
  return table.concat(reply)
end
M.hypr_request = hypr_request

-- Внешнее переключение раскладки (как Super+Пробел): switchxkblayout в .socket.sock
-- двойника. Возврат — после того, как испытуемый nvim увидел новое состояние:
-- ru-layout.layout.get() == code; испытуемый ждёт событие сокета внутри vim.wait
-- по этому условию (ожидание события продукта, не срок).
-- Проверяется layout_spec.lua (модуль ru-layout.layout пишется отдельно).
function M.hypr_switch(code)
  local idx = ({ us = 0, ru = 1 })[code]
  assert(idx, "раскладка us или ru")
  local function seen()
    return M.lua("return require('ru-layout.layout').get() == ...", code)
  end
  if seen() then
    return
  end
  hypr_request(("switchxkblayout %s %d"):format(M.DEVICE, idx))
  M.lua(
    [[local code = ...
    vim.wait(2 ^ 31 - 1, function() return require('ru-layout.layout').get() == code end, 1)]],
    code
  )
end

-- Остановка: nvim — qa! и ожидание выхода; двойник — SIGTERM по pid и ожидание
-- выхода; каталог временного XDG_RUNTIME_DIR и остальные удаляются.
function M.stop()
  if M.ch then
    pcall(vim.rpcnotify, M.ch, "nvim_command", "qa!")
    M.nvim_exit = vim.fn.jobwait({ M.ch }, FOREVER)[1]
    M.ch = nil
  end
  if hypr_job then
    vim.fn.jobstop(hypr_job)
    M.hypr_exit = vim.fn.jobwait({ hypr_job }, FOREVER)[1]
    hypr_job = nil
  end
  if tmp then
    vim.fn.delete(tmp, "rf")
    tmp = nil
  end
end

-- Сброс перед случаем: выход в normal, текст, курсор.
function M.reset(lines, cur)
  M.input("<Esc><Esc>")
  while M.mode().blocking do
    M.input("<Esc>")
  end
  M.sync()
  M.lua("vim.cmd('silent! %bwipe!'); vim.api.nvim_buf_set_lines(0,0,-1,false,...)", lines or { "" })
  M.lua("vim.api.nvim_win_set_cursor(0, ...)", cur or { 1, 0 })
end

-- Случай: сброс, ввод, проверка. check() возвращает факт; opts.verdict(fact) — булево.
function M.case(exp, keys, expect, check, opts)
  opts = opts or {}
  M.reset(opts.lines, opts.cur)
  if opts.pre then
    M.lua(opts.pre)
  end
  M.input(keys)
  local st = M.sync()
  local fact = st:match("^BLOCKING") and st or check()
  local ok
  if opts.verdict then
    ok = opts.verdict(fact)
  end
  M.row(exp, opts.show or keys, expect, fact, ok)
  return fact
end

return M
