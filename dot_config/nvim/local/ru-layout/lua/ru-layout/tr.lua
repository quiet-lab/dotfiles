-- Перевод строк и lhs привязок между раскладками ЙЦУКЕН и QWERTY по таблице
-- `ru-layout.table` (физические клавиши карты XKB).
local T = require("ru-layout.table")

local M = {}

M.ru2us = T.ru_to_us
M.us2ru = T.us_to_ru

-- Символы строки UTF-8 по одному (без vim.fn: функция вызывается на каждую
-- привязку при запуске). Байт продолжения без ведущего байта — отдельный символ.
local function chars(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local j = i + 1
    -- Продолжения собираются только за ведущим байтом многобайтового символа.
    while j <= n and s:byte(i) >= 0xC0 do
      local b = s:byte(j)
      if b < 0x80 or b > 0xBF then
        break
      end
      j = j + 1
    end
    out[#out + 1] = s:sub(i, j - 1)
    i = j
  end
  return out
end
M.chars = chars

-- Один ли символ в строке.
local function single(s)
  return s ~= "" and #chars(s) == 1
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

-- Активная раскладка по ru-layout.layout: "ru" или "us"; неизвестная раскладка,
-- отсутствие Hyprland и модуля layout — "us".
function M.layout()
  local ok, layout = pcall(require, "ru-layout.layout")
  return (ok and layout.get() == "ru") and "ru" or "us"
end

-- Экранирование символа внутри коллекции [] регулярного выражения Vim.
function M.cesc(c)
  if c == "]" or c == "\\" or c == "^" or c == "-" then
    return "\\" .. c
  end
  return c
end

-- Один символ → фрагмент шаблона \V: символ с парой — класс из него и пары
-- (`ы` → `\[ыs]`), остальные — буквально (`\` экранируется). pair(c) — пара
-- символа (по умолчанию M.counterpart).
function M.class(c, pair)
  local d = (pair or M.counterpart)(c)
  if not d then
    return c == "\\" and "\\\\" or c
  end
  return "\\[" .. M.cesc(c) .. M.cesc(d) .. "]"
end

-- Есть ли в строке кириллица (U+0400…U+04FF).
-- В UTF-8 это два байта: ведущий 0xD0…0xD3 и байт продолжения.
local CYR = "^[\208-\211][\128-\191]$"
function M.has_cyrillic(s)
  return s:find("[\208-\211][\128-\191]") ~= nil
end

-- Вся строка состоит из кириллицы и ё (регистр любой); пустая строка не подходит.
function M.is_cyrillic(s)
  if s == "" then
    return false
  end
  for _, c in ipairs(chars(s)) do
    if not c:find(CYR) then
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

-- Имя клавиши в записи <…>: символы, которые внутри <…> пишутся словом.
local NAMES = { ["<"] = "lt", ["\\"] = "Bslash", ["|"] = "Bar" }

-- Латинская форма сочетания с модификатором по физической клавише: mods —
-- строка модификаторов вида "C-", "M-", "C-S-"; c — символ раскладки ru. Заглавная
-- латинская буква уходит в модификатор S (`<C-В>` → `<C-S-d>`, `<M-В>` → `<M-S-d>`,
-- то есть `<M-D>`): так её передаёт терминал, кодирующий клавиши по физическому
-- положению. Возвращает запись `<…>` или nil, если у символа нет пары.
function M.mod_to_us(mods, c)
  local us = M.ru2us[c]
  if not us then
    return nil
  end
  local m = mods:upper():gsub("A%-", "M-")
  if us:match("^%u$") then
    us = us:lower()
    if not m:find("S%-") then
      m = m .. "S-"
    end
  end
  return "<" .. m .. (NAMES[us] or us) .. ">"
end

-- Разбор одной клавиши в записи `<mods-c>`: модификаторы и символ; nil, если это не
-- сочетание с модификатором из C, M, A, D, S или после модификаторов не один символ.
function M.split_mod(key)
  local name = key:match("^<(.+)>$")
  if not name then
    return nil
  end
  local k = 1
  while name:sub(k, k + 1):match("^[CcMmAaDdSs]%-$") do
    k = k + 2
  end
  local mods, c = name:sub(1, k - 1), name:sub(k)
  if k == 1 or not single(c) or not M.has_modifier("<" .. mods) then
    return nil
  end
  return mods, c
end

-- Код клавиши (как его возвращают getcharstr() и vim.keycode()) → латинская форма
-- по физической клавише: `<C-в>` → `<C-d>`, `<M-Ф>` → `<M-A>`. С bare = true
-- переводится и кириллическая буква без модификатора (`в` → `d`). Остальные клавиши
-- возвращаются как есть.
function M.key_to_us(raw, bare)
  if type(raw) ~= "string" or raw == "" then
    return raw
  end
  if raw:byte(1) ~= 0x80 then
    return bare and M.ru2us[raw] or raw
  end
  local mods, c = M.split_mod(vim.fn.keytrans(raw))
  local us = mods and M.mod_to_us(mods, c)
  return us and vim.keycode(us) or raw
end

-- Перевод lhs в латинскую форму только у сочетаний с модификатором (`<C-ц>ч` →
-- `<C-w>ч`, `<M-в>` → `<M-d>`): так lhs, записанный для хоста, передающего
-- кириллицу, набирается на хосте, передающем физическую клавишу. Буквы без
-- модификатора не меняются: их оба вида хостов передают кириллицей.
function M.lhs_mods_to_us(lhs)
  return (
    lhs:gsub("%b<>", function(k)
      local mods, c = M.split_mod(k)
      return mods and M.mod_to_us(mods, c) or k
    end)
  )
end

-- Перевод lhs привязки. Обычные символы вне <…> переводятся по us → ru, но только
-- в кириллицу: ASCII-знаки раскладки ru не подставляются, их ведёт модуль punct.
-- Внутри <…> переводится лишь одиночный символ после модификатора (<M-d> → <M-в>);
-- имена <leader>, <CR>, <Esc>, <F1>, <lt> и прочие остаются как есть; всё после <Plug> и <SNR> тоже.
-- С keep_mods = true сочетания с модификатором не переводятся (`<C-w>x` → `<C-w>ч`):
-- такую форму даёт в русской раскладке хост, передающий сочетания по физической
-- клавише (wezterm), а полную (`<C-ц>ч`) — хост, передающий символ (Neovide).
function M.lhs_to_ru(lhs, keep_mods)
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
        -- `<C-W>` (так пишет keytrans) — то же, что `<C-w>`: Ctrl с латинской буквой
        -- без Shift регистра не различает, а у кириллицы `<C-Ц>` ≠ `<C-ц>`.
        if key:match("^%u$") and mods:upper():find("C%-") and not mods:upper():find("S%-") then
          key = key:lower()
        end
        if k > 1 and single(key) and M.has_modifier("<" .. mods) and not keep_mods then
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
