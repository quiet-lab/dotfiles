-- Поставщик контекста для плагина herdr keys-help (docs/keys-help.md, D2 и D11 изменения herdr-keys-help).
-- Пишет запись о режиме Neovim в каталог панели и отдаёт таблицу привязок функцией dump().
-- Работает только внутри панели herdr (HERDR_PANE_ID), без таймеров: записи — по событиям.
local M = {}

local MODE_NAMES = {
  n = "normal",
  i = "insert",
  v = "visual",
  V = "visual",
  ["\22"] = "visual",
  s = "select",
  S = "select",
  ["\19"] = "select",
  c = "cmdline",
  R = "replace",
  t = "terminal",
}

local last_mode = nil
local record_path = nil

-- Имя режима по строке `mode()`: оператор ожидает объект ("no…"), остальное — по первой букве.
function M.mode_name(raw)
  if raw:sub(1, 2) == "no" then
    return "operator"
  end
  return MODE_NAMES[raw:sub(1, 1)] or "normal"
end

local function runtime_dir()
  local base = vim.env.XDG_RUNTIME_DIR
  if not base or base == "" then
    return nil
  end
  return base .. "/herdr-keys-help/panes/" .. vim.env.HERDR_PANE_ID
end

local function write_record(mode)
  if mode == last_mode or not record_path then
    return
  end
  local file = io.open(record_path, "w")
  if not file then
    return
  end
  last_mode = mode
  -- Запись целиком одним write: просмотрщик читает по IN_CLOSE_WRITE.
  file:write(vim.json.encode({
    v = 1,
    program = "nvim",
    mode = mode,
    pid = vim.uv.os_getpid(),
    state = "active",
    command = vim.NIL,
    table = vim.NIL,
    server = vim.v.servername,
    env = vim.empty_dict(),
  }))
  file:close()
end

local function remove_record()
  if record_path then
    os.remove(record_path)
  end
end

local function config_dir()
  return vim.fn.stdpath("config")
end

-- Происхождение по пути файла определения: каталог конфига, LazyVim, плагин lazy или сам Neovim.
function M.origin_of(path)
  if not path or path == "" then
    return "nvim"
  end
  local plugin = path:match("/lazy/([^/]+)/")
  if plugin == "LazyVim" then
    return "lazyvim"
  end
  if plugin then
    return plugin
  end
  if vim.startswith(path, config_dir()) then
    return "user"
  end
  return "nvim"
end

-- Файл и строка определения привязки: по callback (debug.getinfo), иначе по sid и lnum.
local function definition_of(map)
  if map.callback then
    local info = debug.getinfo(map.callback, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
      return info.source:sub(2), info.linedefined
    end
  end
  if map.sid and map.sid > 0 then
    local ok, infos = pcall(vim.fn.getscriptinfo, { sid = map.sid })
    if ok and infos and infos[1] then
      return infos[1].name, map.lnum
    end
  end
  return nil, nil
end

local function convert(map, buffer)
  local file, line = definition_of(map)
  local origin = M.origin_of(file)
  return {
    lhs = map.lhs,
    rhs = map.rhs,
    desc = map.desc,
    mode = map.mode,
    buffer = buffer,
    origin = origin,
    -- Группа which-key не читается без его внутренних структур: группа — происхождение.
    group = origin,
    source = file and (line and (file .. ":" .. line) or file) or nil,
  }
end

-- JSON-массив глобальных и буферных привязок режима `mode` (по умолчанию "n").
function M.dump(mode)
  mode = mode or "n"
  local result = {}
  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    result[#result + 1] = convert(map, false)
  end
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
    result[#result + 1] = convert(map, true)
  end
  return vim.json.encode(result)
end

function M.setup()
  if not vim.env.HERDR_PANE_ID or vim.env.HERDR_PANE_ID == "" then
    return
  end
  local dir = runtime_dir()
  if not dir then
    return
  end
  vim.fn.mkdir(dir, "p")
  record_path = dir .. "/nvim-" .. vim.uv.os_getpid() .. ".json"
  local group = vim.api.nvim_create_augroup("keys_help", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "ModeChanged" }, {
    group = group,
    callback = function(ev)
      local raw = ev.event == "ModeChanged" and vim.v.event.new_mode or vim.fn.mode()
      write_record(M.mode_name(raw))
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = remove_record })
  -- Автокоманда VimEnter могла пройти до вызова setup (VeryLazy): записать текущий режим сразу.
  if vim.v.vim_did_enter == 1 then
    write_record(M.mode_name(vim.fn.mode()))
  end
end

return M
