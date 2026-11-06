-- Перевод строк и lhs привязок между раскладками ЙЦУКЕН и QWERTY по таблице
-- `ru-layout.table` (физические клавиши карты XKB).
local T = require("ru-layout.table")

local M = {}

M.ru2us = T.ru_to_us
M.us2ru = T.us_to_ru

local function chars(s)
  return vim.fn.split(s, "\\zs")
end

local function is_ascii(c)
  return #c == 1
end

-- Каждый символ строки по таблице ru → us, остальные без изменений.
function M.to_us(s)
  local out = {}
  for i, c in ipairs(chars(s)) do
    out[i] = M.ru2us[c] or c
  end
  return table.concat(out)
end

-- Каждый символ строки по таблице us → ru, остальные без изменений.
function M.to_ru(s)
  local out = {}
  for i, c in ipairs(chars(s)) do
    out[i] = M.us2ru[c] or c
  end
  return table.concat(out)
end

-- Пара символа в другой раскладке: кириллица → клавиша us, латинская клавиша →
-- кириллица (ю↔., б↔,, х↔[ и т. д.). ASCII-знаки раскладки ru (`;`, `.`, `/` и
-- подобные) парой не считаются: их смысл зависит от активной раскладки.
function M.counterpart(c)
  if M.ru2us[c] then
    return M.ru2us[c]
  end
  local ru = M.us2ru[c]
  if ru and not is_ascii(ru) then
    return ru
  end
  return nil
end

-- Вся строка состоит из кириллицы и ё (регистр любой); пустая строка не подходит.
function M.is_cyrillic(s)
  if s == "" then
    return false
  end
  for _, c in ipairs(chars(s)) do
    local cp = vim.fn.char2nr(c)
    if cp < 0x400 or cp > 0x4FF then
      return false
    end
  end
  return true
end

-- Есть ли в lhs модификатор вида <M-…>, <A-…>, <C-…>, <D-…> (в том числе в составе
-- <C-S-x>); регистр модификатора любой.
function M.has_modifier(lhs)
  return lhs:find("<[CcMmAaDd]%-") ~= nil
end

-- Перевод lhs привязки. Обычные символы вне <…> переводятся по us → ru, но только
-- в кириллицу: ASCII-знаки раскладки ru не подставляются, их ведёт модуль punct.
-- Внутри <…> переводится лишь одиночный символ после модификатора (<M-d> → <M-в>);
-- имена <leader>, <CR>, <Esc>, <F1>, <lt> и прочие остаются как есть; всё после <Plug> и <SNR> тоже.
function M.lhs_to_ru(lhs)
  local function conv(c)
    local ru = M.us2ru[c]
    if ru and not is_ascii(ru) then
      return ru
    end
    return c
  end
  local out = {}
  local cs = chars(lhs)
  local i, n = 1, #cs
  while i <= n do
    local c = cs[i]
    local done = false
    if c == "<" then
      -- Ближайший «>» без «<» и пробелов между ними.
      local j = i + 1
      while j <= n and cs[j] ~= ">" and cs[j] ~= "<" and not cs[j]:match("%s") do
        j = j + 1
      end
      if j <= n and cs[j] == ">" and j > i + 1 then
        local name = table.concat(cs, "", i + 1, j - 1)
        -- Модификаторы разбираются вручную: шаблоны Lua не умеют повторять группу.
        local k = 1
        while name:sub(k, k + 1):match("^[CcMmAaDdSs]%-$") do
          k = k + 2
        end
        local mods, key = name:sub(1, k - 1), name:sub(k)
        if k > 1 and vim.fn.strchars(key) == 1 and M.has_modifier("<" .. mods) then
          out[#out + 1] = "<" .. mods .. conv(key) .. ">"
        else
          out[#out + 1] = "<" .. name .. ">"
        end
        i = j + 1
        done = true
        -- После <Plug> и <SNR> идёт имя отображения: остаток lhs не трогается.
        if name:lower() == "plug" or name:lower() == "snr" then
          out[#out + 1] = table.concat(cs, "", i)
          i = n + 1
        end
      end
    end
    if not done then
      out[#out + 1] = conv(c)
      i = i + 1
    end
  end
  return table.concat(out)
end

return M
