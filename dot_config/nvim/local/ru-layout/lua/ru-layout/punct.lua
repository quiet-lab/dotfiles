-- Знаки по раскладке в normal, visual (x) и operator-pending (o).
--
-- В русской раскладке на клавишах `/ ? @ $ ^ & |` стоят ASCII-знаки
-- `. , " ; : ? /`: `langmap` их перевести не может, иначе ломается английская
-- раскладка. Поэтому на семь знаков `table.ru_ascii_to_us` ставятся привязки
-- `expr`: при `layout.get() == "ru"` знак заменяется знаком той же клавиши
-- в английской раскладке (`.` → `/`, `,` → `?`, `"` → `@`, `;` → `$`,
-- `:` → `^`, `?` → `&`, `/` → `|`), иначе выполняется прежнее действие:
-- привязка, которая стояла на клавише до модуля (flash ставит `;` и `,`),
-- или встроенная команда.
--
-- Прежние действия этих знаков в русской раскладке набираются кириллическими
-- клавишами тех же мест (`ю` — повтор `.`, `б`/`ж` — повтор flash `,`/`;`,
-- `Э` — регистр `"`, `Ж` — командная строка `:`). Модуль ставит на них
-- привязки с прежним действием: иначе модуль keymap поставил бы на них дубли
-- привязок-знаков (`.` → `ю`), и `ю` в русской раскладке открывал бы поиск.
--
--   require("ru-layout.punct").setup()
--
-- Порядок: flash ставит `;` и `,` только если клавиши свободны. Пока flash.nvim
-- описан в lazy.nvim, но не загружен, эти две клавиши (и их пары `ж`, `б`)
-- не занимаются. `setup()` повторяется по каждому `User LazyLoad`: свободная
-- клавиша занимается, а привязка, поставленная поверх модуля другим плагином,
-- становится прежним действием. Повторный вызов идемпотентен.
local T = require("ru-layout.table")
local tr = require("ru-layout.tr")

local M = {}

local DESC = "ru-layout: знак по раскладке"
local DESC_PAIR = "ru-layout: прежнее действие знака"
local MODES = { "n", "x", "o" }
-- Порядок знаков постоянный: от него зависят номера в M._slots.
local KEYS = { ".", ",", '"', ";", ":", "?", "/" }
-- Клавиши, которые flash занимает, только если они свободны.
local FLASH_KEYS = { [";"] = true, [","] = true }

-- M._slots[id] = { mode, key, prev }; prev — словарь maparg() прежней привязки
-- или nil (встроенная команда).
M._slots = {}
local slot_of = {} -- slot_of[mode][key] = id

local function slot(mode, key)
  slot_of[mode] = slot_of[mode] or {}
  local id = slot_of[mode][key]
  if not id then
    id = #M._slots + 1
    M._slots[id] = { mode = mode, key = key }
    slot_of[mode][key] = id
  end
  return M._slots[id]
end

local function layout_code()
  local ok, layout = pcall(require, "ru-layout.layout")
  return ok and layout.get() or nil
end

local function tc(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

-- Описан ли плагин в lazy.nvim и ещё не загружен.
local function lazy_pending(name)
  local ok, cfg = pcall(require, "lazy.core.config")
  if not ok or type(cfg.plugins) ~= "table" then
    return false
  end
  local p = cfg.plugins[name]
  return p ~= nil and not (p._ and p._.loaded)
end

-- Вызов прежнего обработчика без expr (из `<Cmd>`): v:count сохраняется.
function M._run(id)
  local s = M._slots[id]
  local prev = s and s.prev
  if not prev then
    return
  end
  if prev.callback then
    return prev.callback()
  end
  -- rhs с привязками: подаётся перед остатком ввода.
  vim.api.nvim_feedkeys(tc(prev.rhs), "im", false)
end

-- Прежнее действие клавиши (строка для expr, коды клавиш уже подставлены).
function M.previous(mode, key)
  local s = slot(mode, key)
  local prev = s.prev
  if not prev then
    return key
  end
  if prev.expr == 1 then
    local r
    if prev.callback then
      r = prev.callback()
    else
      r = vim.api.nvim_eval(prev.rhs)
    end
    r = r or ""
    return prev.replace_keycodes == 1 and tc(r) or r
  end
  if prev.callback or prev.noremap ~= 1 then
    local id = slot_of[mode][key]
    return tc(("<Cmd>lua require('ru-layout.punct')._run(%d)<CR>"):format(id))
  end
  return tc(prev.rhs)
end

-- Тело привязки знака.
function M.action(mode, key)
  if layout_code() == "ru" then
    return T.ru_ascii_to_us[key]
  end
  return M.previous(mode, key)
end

local function ours(m)
  return m and (m.desc == DESC or m.desc == DESC_PAIR)
end

local function install(mode, key)
  local cur = vim.fn.maparg(key, mode, false, true)
  local s = slot(mode, key)
  if ours(cur) then
    if s.installed then
      return
    end
  elseif vim.tbl_isempty(cur) then
    -- Клавиша свободна: прежнее действие — встроенная команда (привязка,
    -- снятая поверх модуля, тоже забывается).
    s.prev = nil
  else
    -- Чужая привязка (до модуля или поставленная поверх него) — прежнее действие.
    s.prev = cur
  end
  local pair = tr.lhs_to_ru(key)
  if pair ~= key then
    -- Сначала пара: так модуль keymap считает её чужой и дубль знака не ставит.
    vim.keymap.set(mode, pair, function()
      return M.previous(mode, key)
    end, { expr = true, replace_keycodes = false, desc = DESC_PAIR })
  end
  -- `"` → `@` должен дойти до обёртки `@` (macro.lua), поэтому remap; возврат
  -- самого `"` в английской раскладке повторно не отображается: rhs начинается
  -- с lhs.
  vim.keymap.set(mode, key, function()
    return M.action(mode, key)
  end, { expr = true, replace_keycodes = false, remap = key == '"', desc = DESC })
  s.installed = true
end

function M.setup()
  local defer_flash = lazy_pending("flash.nvim")
  for _, mode in ipairs(MODES) do
    for _, key in ipairs(KEYS) do
      if not (defer_flash and FLASH_KEYS[key]) then
        install(mode, key)
      end
    end
  end
  if not M._augroup then
    M._augroup = vim.api.nvim_create_augroup("ru-layout-punct", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = M._augroup,
      pattern = "LazyLoad",
      callback = function()
        M.setup()
      end,
    })
  end
end

return M
