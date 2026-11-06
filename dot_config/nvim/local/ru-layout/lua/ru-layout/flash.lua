-- flash.nvim в двух раскладках без правок кода flash.
--
--   * метки по активной раскладке: в ru — набор меток flash (`labels` из
--     конфигурации, у treesitter свой), переведённый по физическим клавишам;
--     раскладка читается у ru-layout.layout в момент вызова flash (событие, не опрос);
--   * поиск по обеим раскладкам: символ с парой становится классом `\[ыs]`;
--   * метка не ставится, если продолжение поиска совпадает с ней или с её парой;
--   * режим char (f/t/F/T, повтор ;/,) ищет символ в обеих раскладках;
--   * интеграция с `/` (modes.search): метки по раскладке;
--   * Backspace в строке поиска flash удаляет символ, а не байт.
--
-- Привязки модуль не ставит: латинские клавиши LazyVim (s, S, r, R, f, t, ;, …)
-- вызывают публичные функции flash, которые оборачивает setup(), а кириллические
-- дубли (ы, Ы, к, К, а, е, ж, б, …) создаёт ru-layout.keymap по правилу дубля.
--
-- Обёртки опираются на внутреннее устройство flash (Char.mode, Labeler.skip,
-- Pattern.extend, plugins.search.start). Перед установкой check() проверяет его;
-- если оно изменилось, модуль ничего не меняет и один раз предупреждает.
--
--   local F = require("ru-layout.flash")
--   F.setup()       -- после загрузки flash; повторный вызов ничего не меняет
--   F.check()       -- true | false, причина
local tr = require("ru-layout.tr")

local M = {}

M.opts = {
  -- искать по обеим раскладкам и знаки на буквенных клавишах (х↔[, ж↔; …), а не только буквы
  punct = true,
}

M.WARNING = "ru-layout: внутренности flash изменились, откатите flash по lazy-lock.json"

-- Флаги живут в таблицах flash: перезагрузка этого модуля не обернёт функции дважды.
local FLAG = "_ru_layout"

local warned = false

-- Активная раскладка: "ru" или "us" (неизвестная и отсутствие Hyprland — "us").
M.layout = tr.layout

-- Пара символа в другой раскладке; без punct — только у букв.
function M.counterpart(c)
  local d = tr.counterpart(c)
  if not d then
    return nil
  end
  if not M.opts.punct then
    local us = tr.ru2us[c] and d or c
    if not us:match("^%a$") then
      return nil
    end
  end
  return d
end

local cesc = tr.cesc

-- Один символ ввода → фрагмент шаблона \V (пара — с учётом opts.punct).
function M.class(c)
  return tr.class(c, M.counterpart)
end

-- search.mode для flash: строка ввода → шаблон поиска и шаблон пропуска меток.
-- Регистр — штатно по ignorecase/smartcase: заглавная даёт класс с заглавными.
function M.mode(str)
  local parts = {}
  for _, c in ipairs(vim.fn.split(str, "\\zs")) do
    parts[#parts + 1] = M.class(c)
  end
  local pat = "\\V" .. table.concat(parts)
  return pat, pat
end

-- Метки в раскладке: в ru — перевод по физическим клавишам.
function M.labels(base, layout)
  if (layout or M.layout()) == "ru" then
    return tr.to_ru(base)
  end
  return base
end

-- Пропуск меток (замена Labeler.skip на экземпляре). Тот же алгоритм, что у flash,
-- но метка снимается, если продолжение поиска совпадает с ней или с её парой,
-- а регистр при ignorecase сравнивается vim.fn.tolower (string.lower не знает кириллицы,
-- и flash при заглавной кириллице в продолжении снимал все метки).
function M.skip(self, win, labels)
  local pattern = self.state.pattern.skip
  if pattern == "" then
    return {}
  end
  if not pcall(vim.regex, pattern) then
    return {}
  end
  if pattern:find("\\$") and not pattern:find("\\\\$") then
    return {}
  end
  local ic = vim.go.ignorecase
  local function fold(c)
    return ic and vim.fn.tolower(c) or c
  end
  local function keep(x, char)
    local d = M.counterpart(x)
    return fold(x) ~= char and not (d and fold(d) == char)
  end
  vim.api.nvim_win_call(win, function()
    while #labels > 0 do
      local probe, seen = {}, {}
      for _, x in ipairs(labels) do
        for _, y in ipairs({ x, M.counterpart(x) or x }) do
          y = fold(y)
          if not seen[y] then
            seen[y] = true
            probe[#probe + 1] = cesc(y)
          end
        end
      end
      local p = "\\%(" .. pattern .. "\\)\\m\\zs[" .. table.concat(probe) .. "]"
      local ok, pos = pcall(vim.fn.searchpos, p, "cnw")
      if not ok then
        labels = {}
        return
      end
      if pos[1] == 0 then
        return
      end
      local line = vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false)[1]
      local char = fold(vim.fn.strpart(line, pos[2] - 1, 1, true))
      local n = #labels
      labels = vim.tbl_filter(function(x)
        return keep(x, char)
      end, labels)
      -- как у flash: ничего не снято — шаблон неполный, меток нет
      if n == #labels then
        labels = {}
        return
      end
    end
  end)
  return labels
end

-- Пропуск меток на время Labeler.new: new() сразу вызывает reset() с пропуском
-- меток (searchpos по каждому окну), а update() ниже всё равно делает reset()
-- заново, уже с M.skip; метки, оставленные здесь, отбрасываются.
local function no_skip(_, _, labels)
  return labels
end

-- labeler для flash: стандартный Labeler с пропуском меток по паре.
function M.labeler(_, state)
  if not state._ru_labeler then
    local Labeler = require("flash.labeler")
    local orig = Labeler.skip
    Labeler.skip = no_skip
    local ok, l = pcall(Labeler.new, state)
    Labeler.skip = orig
    if not ok then
      error(l, 0)
    end
    l.skip = M.skip
    state._ru_labeler = l
  end
  state._ru_labeler:update()
end

-- Параметры вызова flash для текущей раскладки; явные opts вызывающего главнее.
--   mode — режим flash, из которого берётся набор меток (nil, "treesitter", …);
--   full — кроме меток, поиск по обеим раскладкам и пропуск меток по паре.
function M.opts_for(mode, opts, full)
  local extra = {}
  if M.layout() == "ru" then
    local Config = require("flash.config")
    extra.labels = M.labels(Config.get(mode and { mode = mode } or nil, opts).labels, "ru")
  end
  if full then
    extra.search = { mode = M.mode }
    extra.labeler = M.labeler
  end
  return vim.tbl_deep_extend("force", extra, opts or {})
end

-- Проверка внутреннего устройства flash, на которое опираются обёртки.
function M.check()
  local function need(ok, what)
    if not ok then
      error(what, 0)
    end
  end
  local ok, err = pcall(function()
    local C = require("flash.commands")
    for _, name in ipairs({ "jump", "treesitter", "treesitter_search", "remote" }) do
      need(type(C[name]) == "function", "flash.commands." .. name)
    end
    local Char = require("flash.plugins.char")
    need(type(Char.mode) == "function", "flash.plugins.char.mode")
    need(type(Char.mode("f")) == "function", "flash.plugins.char.mode(motion)")
    local Labeler = require("flash.labeler")
    need(type(Labeler.new) == "function", "flash.labeler.new")
    -- skip — метод, который Labeler:reset() вызывает через self: экземпляр new(...)
    -- находит его в метатаблице Labeler
    need(Labeler.__index == Labeler and type(Labeler.skip) == "function", "flash.labeler.skip")
    need(type(Labeler.update) == "function", "flash.labeler.update")
    local Pattern = require("flash.search.pattern")
    need(type(Pattern.extend) == "function", "flash.search.pattern.extend")
    local Search = require("flash.plugins.search")
    need(type(Search.start) == "function", "flash.plugins.search.start")
  end)
  return ok, not ok and err or nil
end

-- Режим char: символ ищется в обеих раскладках (замена Char.mode).
function M.patch_char()
  local Char = require("flash.plugins.char")
  local Config = require("flash.config")
  if Char[FLAG] then
    return
  end
  Char[FLAG] = Char.mode
  Char.mode = function(motion)
    return function(c)
      local cls = M.class(c)
      local pattern
      if motion == "t" then
        pattern = "\\m.\\ze\\V" .. cls
      elseif motion == "T" then
        pattern = "\\V" .. cls .. "\\zs\\m."
      else
        pattern = "\\V" .. cls
      end
      if not Config.get("char").multi_line then
        pattern = ("\\%%%dl"):format(vim.api.nvim_win_get_cursor(0)[1]) .. pattern
      end
      return pattern
    end
  end
end

-- Публичные функции flash: метки по раскладке, поиск и пропуск по обеим.
local function wrap_commands()
  local C = require("flash.commands")
  if C[FLAG] then
    return
  end
  local orig = {}
  C[FLAG] = orig
  local spec = {
    jump = { nil, true },
    treesitter = { "treesitter", false },
    treesitter_search = { "treesitter_search", true },
    remote = { "remote", true },
  }
  for name, s in pairs(spec) do
    orig[name] = C[name]
    C[name] = function(opts)
      return orig[name](M.opts_for(s[1], opts, s[2]))
    end
  end
end

-- Backspace в строке поиска flash: flash отрезает последний байт, и кириллица
-- превращается в обломок UTF-8; здесь удаляется последний символ.
local function patch_pattern()
  local Pattern = require("flash.search.pattern")
  if Pattern[FLAG] then
    return
  end
  local orig = Pattern.extend
  Pattern[FLAG] = orig
  local BS = require("flash.util").BS
  Pattern.extend = function(self, char)
    if char == BS then
      return vim.fn.strcharpart(self.pattern, 0, vim.fn.strchars(self.pattern) - 1)
    end
    return orig(self, char)
  end
end

-- Интеграция с `/` (modes.search, переключатель <c-s>): метки по раскладке на время
-- строки поиска, пропуск меток по паре.
local function patch_search()
  local Search = require("flash.plugins.search")
  if Search[FLAG] then
    return
  end
  local orig = Search.start
  Search[FLAG] = orig
  Search.start = function(...)
    local ret = orig(...)
    local st = Search.state
    if st then
      st.opts.labels = M.labels(st.opts.labels)
      st.labeler = M.labeler
    end
    return ret
  end
end

-- Установка обёрток; вызывается после загрузки flash. Повторный вызов ничего не меняет.
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  local ok, err = M.check()
  if not ok then
    if not warned then
      warned = true
      vim.notify(M.WARNING .. " (" .. tostring(err) .. ")", vim.log.levels.WARN)
    end
    return false
  end
  wrap_commands()
  M.patch_char()
  patch_pattern()
  patch_search()
  return true
end

return M
