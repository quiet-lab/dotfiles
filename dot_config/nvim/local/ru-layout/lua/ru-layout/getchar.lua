-- Перевод клавиш, которые плагин читает сам (`getchar()`, `getcharstr()`), на время
-- синхронного вызова его функции: кириллическая буква, набранная в раскладке ЙЦУКЕН,
-- возвращается латинской буквой той же физической клавиши (`ы` → `s`). Глобальной
-- подмены нет: она сломала бы русский поиск flash и ввод текста.
local tr = require("ru-layout.tr")

local M = {}

local fn = vim.fn
-- Глубина вложенных вызовов with_tr и исходные функции внешнего вызова.
local depth = 0
local saved_getchar, saved_getcharstr
-- Обёртки, созданные модулем: повторно не оборачиваются.
local wrappers = setmetatable({}, { __mode = "k" })

local function tr_str(c)
  if type(c) == "string" then
    return tr.ru2us[c] or c
  end
  return c
end

local function tr_nr(c)
  if type(c) == "number" and c > 127 then
    local us = tr.ru2us[fn.nr2char(c)]
    if us then
      return fn.char2nr(us)
    end
  end
  return c
end

-- Вызов fn(...) с переводом vim.fn.getchar/getcharstr. Возвращает все значения fn;
-- ошибка fn пробрасывается дальше после восстановления исходных функций. Во
-- вложенном вызове подмена уже стоит, восстанавливает её только внешний вызов.
function M.with_tr(f, ...)
  if depth == 0 then
    saved_getchar, saved_getcharstr = fn.getchar, fn.getcharstr
    local gc, gs = saved_getchar, saved_getcharstr
    fn.getchar = function(...)
      return tr_nr(gc(...))
    end
    fn.getcharstr = function(...)
      return tr_str(gs(...))
    end
  end
  depth = depth + 1
  local r = vim.F.pack_len(pcall(f, ...))
  depth = depth - 1
  if depth == 0 then
    fn.getchar, fn.getcharstr = saved_getchar, saved_getcharstr
    saved_getchar, saved_getcharstr = nil, nil
  end
  if not r[1] then
    error(r[2], 0)
  end
  return unpack(r, 2, r.n)
end

-- Функция-обёртка: f с переводом на время вызова. Обёртка над обёрткой не строится.
function M.wrap_fn(f)
  if wrappers[f] then
    return f
  end
  local w = function(...)
    return M.with_tr(f, ...)
  end
  wrappers[w] = f
  return w
end

-- Признак обёртки модуля и исходная функция под ней.
function M.is_wrapped(f)
  return wrappers[f] ~= nil, wrappers[f]
end

-- tbl[name] заменяется обёрткой над прежней функцией; повторный вызов ничего не
-- меняет. Возвращает true, если функция найдена.
function M.wrap(tbl, name)
  local f = type(tbl) == "table" and tbl[name] or nil
  if type(f) ~= "function" then
    return false
  end
  tbl[name] = M.wrap_fn(f)
  return true
end

return M
