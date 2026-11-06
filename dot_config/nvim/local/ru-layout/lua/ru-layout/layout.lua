-- Раскладка клавиатуры из Hyprland.
--
-- Источник сведений — сокеты экземпляра Hyprland ($XDG_RUNTIME_DIR/hypr/<подпись>):
--   .socket.sock  — запросы: один j/devices при подключении и switchxkblayout;
--   .socket2.sock — события, строки «activelayout>>DEVICE,KEYMAP».
-- Таймеров и опроса нет: состояние меняется только по событию сокета,
-- переподключение — по событию файловой системы (inotify через vim.uv.new_fs_event):
-- появление каталога hypr, каталога экземпляра и его сокетов.
--
--   local layout = require("ru-layout.layout")
--   layout.setup({ device = "dh747-w-corne" })  -- false, если Hyprland не найден
--   layout.get()             --> "us" | "ru" | nil (Hyprland не найден или состояние неизвестно)
--   layout.switch_to("us", cb)
--   layout.info()
--   autocmd User LayoutChanged, data = { old, new } — после каждой смены кода раскладки,
--   в том числе на nil при обрыве связи с Hyprland.

local uv = vim.uv
local M = {}

local defaults = {
  -- Устройство, раскладку которого отслеживает модуль. Имя надёжнее поля main
  -- в j/devices: main — клавиатура сиденья, она меняется (после wtype ею становится
  -- виртуальная клавиатура или кнопка питания). nil — main на момент подключения.
  device = "dh747-w-corne",
  -- Имя раскладки XKB (active_keymap) → короткий код.
  names = { ["English (US)"] = "us", ["Russian"] = "ru" },
  -- Код → номер группы XKB (порядок в карте: pc+us+ru:2).
  indices = { us = 0, ru = 1 },
}

local S = {
  opts = vim.deepcopy(defaults),
  enabled = false, -- подключён к экземпляру Hyprland
  base = nil, -- каталог экземпляра $XDG_RUNTIME_DIR/hypr/<подпись>
  device = nil,
  keymap = nil, -- active_keymap устройства
  code = nil, -- "us" | "ru" | имя раскладки без кода
  index = nil,
  ev = nil, -- труба .socket2.sock
  buf = "",
  watchers = {}, -- uv_fs_event_t на время ожидания экземпляра
  watched = {}, -- пути, за которыми уже следят
  requests = 0, -- число запросов к .socket.sock (для проверок)
}

local function code_of(keymap)
  if not keymap then
    return nil
  end
  return S.opts.names[keymap] or keymap
end

-- Каталог экземпляра: подпись из окружения, если её сокеты существуют,
-- иначе самый свежий каталог $XDG_RUNTIME_DIR/hypr с обоими сокетами.
-- Второе значение — каталог hypr, третье — $XDG_RUNTIME_DIR.
local function find_base()
  local rt = vim.env.XDG_RUNTIME_DIR
  if not rt or rt == "" then
    return nil
  end
  local root = rt .. "/hypr"
  local function has_sockets(dir)
    return uv.fs_stat(dir .. "/.socket2.sock") and uv.fs_stat(dir .. "/.socket.sock")
  end
  local sig = vim.env.HYPRLAND_INSTANCE_SIGNATURE
  if sig and sig ~= "" and has_sockets(root .. "/" .. sig) then
    return root .. "/" .. sig, root, rt
  end
  local best, best_t
  local h = uv.fs_scandir(root)
  while h do
    local name, typ = uv.fs_scandir_next(h)
    if not name then
      break
    end
    local dir = root .. "/" .. name
    if typ == "directory" and has_sockets(dir) then
      local st = uv.fs_stat(dir)
      local t = st and (st.mtime.sec + st.mtime.nsec / 1e9) or 0
      if not best_t or t > best_t then
        best, best_t = dir, t
      end
    end
  end
  return best, root, rt
end

-- Один запрос к .socket.sock; ответ приходит целиком до закрытия сокета сервером.
local function request(cmd, cb)
  if not S.base then
    return vim.schedule(function()
      cb(nil, "no hyprland")
    end)
  end
  S.requests = S.requests + 1
  local pipe = uv.new_pipe(false)
  local chunks = {}
  pipe:connect(S.base .. "/.socket.sock", function(err)
    if err then
      pipe:close()
      return vim.schedule(function()
        cb(nil, err)
      end)
    end
    pipe:write(cmd)
    pipe:read_start(function(rerr, data)
      if data then
        chunks[#chunks + 1] = data
        return
      end
      pipe:close()
      vim.schedule(function()
        cb(not rerr and table.concat(chunks) or nil, rerr)
      end)
    end)
  end)
end

-- Новое состояние: событие User LayoutChanged, если код изменился.
local function set_code(keymap)
  local old = S.code
  S.keymap = keymap
  S.code = code_of(keymap)
  if S.code and S.opts.indices[S.code] then
    S.index = S.opts.indices[S.code]
  end
  if old ~= S.code then
    vim.api.nvim_exec_autocmds("User", {
      pattern = "LayoutChanged",
      modeline = false,
      data = { old = old, new = S.code },
    })
  end
end

-- Начальное состояние: один запрос j/devices.
local function query_devices()
  local base = S.base
  request("j/devices", function(out)
    if not out or S.base ~= base or not S.ev then
      return
    end
    local ok, d = pcall(vim.json.decode, out)
    if not ok or type(d) ~= "table" then
      return
    end
    local kb
    for _, k in ipairs(d.keyboards or {}) do
      if (S.opts.device and k.name == S.opts.device) or (not S.opts.device and k.main) then
        kb = k
      end
    end
    if not kb then
      return
    end
    S.device = kb.name
    S.index = kb.active_layout_index
    set_code(kb.active_keymap)
  end)
end

-- Разбор строки событий: имя устройства — до первой запятой (в имени раскладки
-- запятые бывают, в имени устройства — нет). События других устройств
-- (виртуальные клавиатуры wtype, другие клавиатуры) пропускаются.
local function on_line(line)
  local dev, keymap = line:match("^activelayout>>([^,]*),(.*)$")
  if dev and S.device and dev == S.device then
    set_code(keymap)
  end
end

local connect_events

local function stop_watchers()
  for _, w in ipairs(S.watchers) do
    if not w:is_closing() then
      w:stop()
      w:close()
    end
  end
  S.watchers = {}
  S.watched = {}
end

-- Ожидание экземпляра по событиям файловой системы, без таймера.
-- Inotify в Linux не рекурсивен, поэтому наблюдатели стоят на $XDG_RUNTIME_DIR
-- (пока нет каталога hypr), на каталоге hypr и на каждом его подкаталоге
-- (сокеты экземпляра появляются в нём позже самого каталога).
local function watch_for_instance(root, rt)
  if not root or #S.watchers > 0 then
    return
  end
  local function try()
    if #S.watchers == 0 then
      return
    end
    local base = find_base()
    if base and connect_events(base) then
      stop_watchers()
    end
  end
  local watch
  local function watch_root()
    if S.watched[root] then
      return
    end
    watch(root)
    -- Подкаталоги, появившиеся до наблюдателя, тоже ждут своих сокетов.
    local h = uv.fs_scandir(root)
    while h do
      local name, typ = uv.fs_scandir_next(h)
      if not name then
        break
      end
      if typ == "directory" then
        watch(root .. "/" .. name)
      end
    end
  end
  watch = function(path)
    if S.watched[path] then
      return
    end
    local w = uv.new_fs_event()
    if
      not w
      or not w:start(path, {}, function(err, fname)
        if err then
          return
        end
        vim.schedule(function()
          if #S.watchers == 0 then
            return
          end
          if path == rt then
            if fname == "hypr" and uv.fs_stat(root) then
              watch_root()
            end
          elseif path == root and fname and uv.fs_stat(root .. "/" .. fname .. "/") then
            watch(root .. "/" .. fname)
          end
          try()
        end)
      end)
    then
      if w then
        w:close()
      end
      return
    end
    S.watched[path] = true
    S.watchers[#S.watchers + 1] = w
  end
  if uv.fs_stat(root) then
    watch_root()
  elseif rt and uv.fs_stat(rt) then
    watch(rt)
  end
  -- Экземпляр мог появиться между проверкой и установкой наблюдателей.
  try()
end

-- Закрыть трубу событий без переподключения.
local function close_events()
  local ev = S.ev
  S.ev = nil
  if ev and not ev:is_closing() then
    ev:close()
  end
end

local function on_disconnect()
  close_events()
  S.enabled = false
  if S.code ~= nil or S.keymap ~= nil then
    set_code(nil) -- состояние неизвестно, пока нет нового экземпляра
  end
  -- Hyprland мог перезапуститься до этого места: сразу пробуем новый экземпляр,
  -- иначе ждём событий файловой системы.
  local base, root, rt = find_base()
  if not (base and base ~= S.base and connect_events(base)) then
    watch_for_instance(root, rt)
  end
end

-- Подключение к .socket2.sock. Подключение асинхронное: успех возвращается
-- сразу, если файлы сокетов существуют; ошибка придёт в обратный вызов.
function connect_events(base)
  if not (uv.fs_stat(base .. "/.socket2.sock") and uv.fs_stat(base .. "/.socket.sock")) then
    return false
  end
  close_events()
  S.base = base
  S.enabled = true
  S.device = S.opts.device
  local pipe = uv.new_pipe(false)
  S.ev = pipe
  S.buf = ""
  pipe:connect(base .. "/.socket2.sock", function(err)
    if err then
      return vim.schedule(function()
        if S.ev == pipe then
          on_disconnect()
        end
      end)
    end
    pipe:read_start(function(rerr, data)
      vim.schedule(function()
        if S.ev ~= pipe then
          return
        end
        if not data then
          return on_disconnect()
        end
        S.buf = S.buf .. data
        while true do
          local nl = S.buf:find("\n", 1, true)
          if not nl then
            break
          end
          local line = S.buf:sub(1, nl - 1)
          S.buf = S.buf:sub(nl + 1)
          on_line(line)
        end
      end)
    end)
    -- Запрос состояния после подписки: изменение между запросом и подпиской не теряется.
    vim.schedule(function()
      if S.ev == pipe then
        query_devices()
      end
    end)
  end)
  return true
end

-- Подключение к Hyprland. Повторный вызов с тем же устройством при живом
-- подключении только обновляет параметры; иначе прежние труба и наблюдатели
-- закрываются, поэтому подписки и наблюдатели не множатся.
function M.setup(opts)
  local new_opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local same_device = new_opts.device == S.opts.device
  S.opts = new_opts
  local base, root, rt = find_base()
  if S.ev and same_device and base == S.base then
    return true
  end
  close_events()
  stop_watchers()
  S.enabled = false
  S.device = S.opts.device
  if S.code ~= nil or S.keymap ~= nil then
    set_code(nil)
  end
  if base and connect_events(base) then
    return true
  end
  -- Hyprland нет (TTY, ssh, другой композитор): модуль отключён, get() → nil;
  -- при появлении экземпляра подключится сам.
  watch_for_instance(root, rt)
  return false
end

-- Синхронно, из состояния.
function M.get()
  return S.code
end

function M.info()
  return {
    enabled = S.enabled,
    base = S.base,
    device = S.device,
    keymap = S.keymap,
    code = S.code,
    index = S.index,
    connected = S.ev ~= nil,
    waiting = #S.watchers > 0,
  }
end

-- Переключение без процесса hyprctl: команда switchxkblayout в .socket.sock.
-- Состояние меняется по событию activelayout, а не здесь. Возвращает false,
-- если переключить нельзя (нет Hyprland, неизвестный код); cb(ok) — по ответу сокета.
function M.switch_to(code, cb)
  local idx = S.opts.indices[code]
  if not (S.enabled and S.device and idx) then
    return false
  end
  if code == S.code then
    if cb then
      vim.schedule(function()
        cb(true)
      end)
    end
    return true
  end
  request(string.format("switchxkblayout %s %d", S.device, idx), function(out)
    if cb then
      cb(out == "ok")
    end
  end)
  return true
end

-- Для проверок: внутреннее состояние и подача строки событий в разборщик.
function M._state()
  return S
end

function M._feed(line)
  on_line(line)
end

return M
