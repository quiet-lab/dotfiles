-- Командная строка без переключения системной раскладки.
--
-- `<CR>` в `:` переводит строку по физическим клавишам: диапазон, командное слово
-- и флаги — в латиницу, аргументы-текст остаются как набраны. `<Tab>` в `:` перед
-- дополнением переводит текст до курсора по тому же правилу и вызывает прежнее
-- действие клавиши (blink.cmp или встроенное дополнение). `<M-l>` в `/` и `?`
-- переписывает шаблон в поиск по обеим раскладкам и обратно.
-- Правило перевода и таблица примеров — заметка задачи (раздел «Правило перевода»).
local tr = require("ru-layout.tr")

local M = {}

local DESC_CR = "ru-layout: перевод строки : по раскладке"
local DESC_TAB = "ru-layout: перевод слова перед дополнением"
local DESC_BOTH = "ru-layout: шаблон по обеим раскладкам"

local function set(list)
  local t = {}
  for _, v in ipairs(list) do
    t[v] = true
  end
  return t
end

-- Модификаторы команд: после них идёт ещё одна команда со своим диапазоном.
local MODIFIERS = set({
  "aboveleft",
  "belowright",
  "botright",
  "browse",
  "confirm",
  "hide",
  "horizontal",
  "keepalt",
  "keepjumps",
  "keepmarks",
  "keeppatterns",
  "leftabove",
  "lockmarks",
  "noautocmd",
  "noswapfile",
  "rightbelow",
  "sandbox",
  "silent",
  "tab",
  "topleft",
  "unsilent",
  "verbose",
  "vertical",
})

-- Встроенные команды, чьи аргументы — ключевые слова (опции, имена, теги справки).
local KEYWORD_CMDS = set({
  "setfiletype",
  "filetype",
  "syntax",
  "colorscheme",
  "highlight",
  "echohl",
  "augroup",
  "doautocmd",
  "doautoall",
  "help",
  "packadd",
  "compiler",
  "messages",
  "language",
  "history",
  "sign",
  "syntime",
  "checkhealth",
  "delcommand",
  "delfunction",
  "unlet",
  "lockvar",
  "unlockvar",
})

-- Значения поля `complete` пользовательских команд, при которых аргументы —
-- ключевые слова. Прочие (file, dir, buffer, expression, shellcmd, lua…) и команды
-- без дополнения считаются текстовыми.
local KEYWORD_COMPLETE = set({
  "custom",
  "customlist",
  "command",
  "option",
  "mapping",
  "event",
  "augroup",
  "color",
  "compiler",
  "filetype",
  "help",
  "highlight",
  "history",
  "locale",
  "messages",
  "packadd",
  "sign",
  "syntax",
  "syntime",
  "user",
  "var",
  "checkhealth",
  "function",
  "keymap",
  "behave",
  "breakpoint",
})

-- Привязки режимов n/x/o: кириллическая левая часть с langmap не срабатывает, поэтому
-- она переводится. В i/c/t/l/s и в `map!` кириллица осмысленна и остаётся.
local NVO_MAPS = set({
  "map",
  "nmap",
  "vmap",
  "xmap",
  "omap",
  "noremap",
  "nnoremap",
  "vnoremap",
  "xnoremap",
  "onoremap",
  "unmap",
  "nunmap",
  "vunmap",
  "xunmap",
  "ounmap",
})

local SET_CMDS = set({ "set", "setlocal", "setglobal" })
local SUB_CMDS = set({ "substitute" })
local GLOBAL_CMDS = set({ "global", "vglobal" })
local SUB_FLAGS = set(vim.split("&cegiInp#lr", ""))

-- Символ UTF-8, начинающийся с байта i, или nil в конце строки.
local function charat(s, i)
  return s:match("^[%z\1-\127\194-\244][\128-\191]*", i)
end

-- Символ раскладки ru, у которого есть пара (кириллица, ё, №).
local function is_cyr(c)
  return c ~= nil and #c > 1 and tr.ru2us[c] ~= nil
end

-- Кириллическая буква, чья клавиша в us — латинская буква (у х ъ ж э б ю ё пары — знаки).
local function cyr_letter(c)
  return is_cyr(c) and tr.ru2us[c]:match("^%a$") ~= nil
end

local function us_of(c)
  return tr.ru2us[c] or c
end

-- Лексема переводима: есть кириллица и нет латинских букв.
local function translatable(tok)
  if tok:find("%a") then
    return false
  end
  local i = 1
  while i <= #tok do
    local c = charat(tok, i)
    if is_cyr(c) then
      return true
    end
    i = i + #c
  end
  return false
end

-- Строка из одних русских букв с необязательным «!» (D4): переводится целиком.
local all_russian = vim.regex([[\v^[а-яёА-ЯЁ]+!?$]])

-- Позиция после закрывающего разделителя d (с учётом «\»), начиная с байта q; nil — нет.
local function skip_delim(s, q, d)
  while q <= #s do
    local c = s:sub(q, q)
    if c == "\\" then
      q = q + 2
    elseif c == d then
      return q + 1
    else
      q = q + 1
    end
  end
  return nil
end

-- Разделитель шаблона `:s` и `:g`: однобайтовый знак, кроме «\», «"», «|».
local function is_delim(d)
  return d ~= "" and d:match("^%p$") ~= nil and not d:match('[\\"|]')
end

-- Есть ли среди дополнений командной строки `prefix` вариант, начинающийся с `word`.
-- Для справки достаточно любого найденного тега: её дополнение ищет и внутри имени.
local function completes(prefix, word, full)
  local ok, list = pcall(vim.fn.getcompletion, prefix, "cmdline")
  if not ok or type(list) ~= "table" then
    return false
  end
  if full == "help" then
    return #list > 0
  end
  local w = word:lower()
  for _, item in ipairs(list) do
    if type(item) == "string" and vim.startswith(item:lower(), w) then
      return true
    end
  end
  return false
end

-- Обход лексем аргументов: fn(prefix, tok, n) возвращает замену лексемы.
local function map_tokens(head, rest, fn)
  local out, pos, n = {}, 1, 0
  while pos <= #rest do
    local ws = rest:match("^%s*", pos)
    out[#out + 1] = ws
    pos = pos + #ws
    local tok = rest:match("^%S+", pos)
    if not tok then
      break
    end
    n = n + 1
    pos = pos + #tok
    out[#out + 1] = fn(head .. table.concat(out), tok, n)
  end
  return table.concat(out)
end

-- Аргументы-ключевые слова: переводимая лексема заменяется переводом, если такое
-- слово предлагает дополнение. limit — сколько первых лексем рассматривать.
local function keyword_args(head, rest, full, limit)
  return map_tokens(head, rest, function(prefix, tok, n)
    if n > limit or not translatable(tok) then
      return tok
    end
    local cand = tr.to_us(tok)
    return completes(prefix .. cand, cand, full) and cand or tok
  end)
end

-- Аргументы `:set`: имя опции (с no/inv) переводится, если опция есть или дополняется;
-- значение — если его предлагает дополнение значения этой опции.
local function set_args(head, rest)
  return map_tokens(head, rest, function(prefix, tok)
    local name, tail = tok:match("^([^=:+%-%^!&?<]*)(.*)$")
    if translatable(name) then
      local cand = tr.to_us(name)
      local base = cand:gsub("^no", ""):gsub("^inv", "")
      if
        vim.fn.exists("+" .. cand) == 1
        or vim.fn.exists("+" .. base) == 1
        or completes(prefix .. cand, cand, "set")
      then
        name = cand
      end
    end
    local op, val = tail:match("^([+%-%^]?[=:])(.*)$")
    if op and translatable(val) then
      local cand = tr.to_us(val)
      if completes(prefix .. name .. op .. cand, cand, "set") then
        tail = op .. cand
      end
    end
    return name .. tail
  end)
end

-- Привязки n/x/o: в левой части кириллица вне <…> переводится, правая часть — текст.
local function map_args(rest)
  local done = false
  return map_tokens("", rest, function(_, tok)
    if done or (tok:match("^<%a+>$") and not tok:match("^<[%a]%-")) then
      return tok
    end
    done = true
    local out, pos = {}, 1
    while pos <= #tok do
      local a, b = tok:find("<[^<>]+>", pos)
      if not a then
        out[#out + 1] = tr.to_us(tok:sub(pos))
        break
      end
      out[#out + 1] = tr.to_us(tok:sub(pos, a - 1)) .. tok:sub(a, b)
      pos = b + 1
    end
    return table.concat(out)
  end)
end

-- Флаги `:s`: кириллица, чья клавиша — флаг, переводится; разбор до первого
-- символа, который флагом не является (счётчик, «|» и прочее остаются как есть).
local function sub_flags(t)
  local out, i = {}, 1
  while i <= #t do
    local c = charat(t, i)
    if SUB_FLAGS[c] then
      out[#out + 1] = c
    elseif is_cyr(c) and SUB_FLAGS[tr.ru2us[c]] then
      out[#out + 1] = tr.ru2us[c]
    else
      break
    end
    i = i + #c
  end
  return table.concat(out) .. t:sub(i)
end

-- Аргументы `:s`: шаблон и замена как набраны, флаги переводятся.
local function sub_args(rest)
  local ws = rest:match("^%s*")
  local p = #ws + 1
  local d = rest:sub(p, p)
  if not is_delim(d) then
    return ws .. sub_flags(rest:sub(p))
  end
  local q = skip_delim(rest, p + 1, d)
  q = q and skip_delim(rest, q, d)
  if not q then
    return rest
  end
  return rest:sub(1, q - 1) .. sub_flags(rest:sub(q))
end

local translate_cmd

-- Аргументы `:g`/`:v`: шаблон как набран, команда после него — по общему правилу.
local function global_args(rest)
  local ws = rest:match("^%s*")
  local p = #ws + 1
  local d = rest:sub(p, p)
  if not is_delim(d) then
    return rest
  end
  local q = skip_delim(rest, p + 1, d)
  if not q then
    return rest
  end
  return rest:sub(1, q - 1) .. translate_cmd(rest:sub(q))
end

-- Диапазон: числа, `.`, `$`, `%`, `+`, `-`, `,`, `;`, отметки, шаблоны `/…/` и `?…?`.
-- Кириллица на месте знака диапазона (ю → `.`, б → `,`, ж → `;`, э → `'`, буква
-- отметки) переводится, шаблоны остаются как набраны.
local function scan_range(s, i, out)
  while true do
    local c = charat(s, i)
    if not c then
      break
    end
    local u = us_of(c)
    if u:match("^[%d%.%$%%%+%-,;%s]$") then
      out[#out + 1] = u
      i = i + #c
    elseif u == "'" then
      out[#out + 1] = "'"
      i = i + #c
      local m = charat(s, i)
      if m then
        out[#out + 1] = us_of(m)
        i = i + #m
      end
    elseif c == "/" or c == "?" then
      local j = skip_delim(s, i + 1, c) or #s + 1
      out[#out + 1] = s:sub(i, j - 1)
      i = j
    elseif c == "\\" and s:sub(i + 1, i + 1):match("[/?&]") then
      out[#out + 1] = s:sub(i, i + 1)
      i = i + 2
    else
      break
    end
  end
  return i
end

-- Командное слово: латинские буквы или кириллица, чьи клавиши — буквы; `Б`/`Ю` —
-- команды сдвига `<`/`>`. Возвращает перевод, позицию после слова и признаки.
local function scan_word(s, i)
  local w, lat, cyr = {}, false, false
  while true do
    local c = charat(s, i)
    if not c then
      break
    end
    if c:match("^%a$") then
      lat = true
      w[#w + 1] = c
    elseif cyr_letter(c) then
      cyr = true
      w[#w + 1] = tr.ru2us[c]
    else
      break
    end
    i = i + #c
  end
  if #w == 0 then
    while true do
      local c = charat(s, i)
      local u = c and us_of(c)
      if not (u == "<" or u == ">") then
        break
      end
      cyr = cyr or is_cyr(c)
      w[#w + 1] = u
      i = i + #c
    end
  end
  return table.concat(w), i, lat, cyr
end

-- Пользовательская команда (буферная или глобальная) по полному имени.
local function user_command(name)
  local ok, cmds = pcall(vim.api.nvim_buf_get_commands, 0, {})
  local c = ok and cmds[name]
  if not c then
    ok, cmds = pcall(vim.api.nvim_get_commands, {})
    c = ok and cmds[name]
  end
  return c or nil
end

local function translate_args(full, head, rest)
  if SUB_CMDS[full] then
    return sub_args(rest)
  elseif GLOBAL_CMDS[full] then
    return global_args(rest)
  elseif SET_CMDS[full] then
    return set_args(head, rest)
  elseif NVO_MAPS[full] then
    return map_args(rest)
  elseif full == "autocmd" then
    return keyword_args(head, rest, full, 2)
  elseif KEYWORD_CMDS[full] then
    return keyword_args(head, rest, full, math.huge)
  end
  local uc = full:match("^%u") and user_command(full)
  local comp = uc and uc.complete
  -- Дополнение функцией Lua (`complete = function`) — список ключевых слов, как customlist.
  if type(comp) == "function" or (type(comp) == "string" and KEYWORD_COMPLETE[comp]) then
    return keyword_args(head, rest, full, math.huge)
  end
  return rest
end

-- Перевод одной команды (без разбора «|»): голова — по клавишам, аргументы — по виду
-- команды. Строка с латиницей в командном слове возвращается как набрана.
function translate_cmd(s)
  if s == "" then
    return s
  end
  if all_russian:match_str(s) then
    return tr.to_us(s)
  end
  local out = {}
  local lead = s:match("^[%s:]*")
  out[1] = lead
  local i = scan_range(s, #lead + 1, out)
  local word, j, lat, cyr = scan_word(s, i)
  if lat and cyr then
    return s
  end
  i = j
  out[#out + 1] = word
  if s:sub(i, i) == "!" then
    out[#out + 1] = "!"
    i = i + 1
  end
  local full = ""
  if word:match("^%a") then
    local ok, f = pcall(vim.fn.fullcommand, word)
    full = ok and f or ""
  elseif word ~= "" then
    full = word:sub(1, 1)
  end
  local head = table.concat(out)
  local rest = s:sub(i)
  if MODIFIERS[full] then
    return head .. translate_cmd(rest)
  end
  if lat then
    -- Латинское командное слово: строка как набрана.
    return s
  end
  return head .. translate_args(full, head, rest)
end

-- Перевод строки `:` по правилу модуля; без изменений, если переводить нечего.
function M.translate(line)
  local ok, res = pcall(translate_cmd, line)
  return ok and res or line
end

-- Шаблон поиска «по обеим раскладкам»: `\V`, каждый символ с парой — класс из него
-- и пары (`ы` → `\[ыs]`), остальные — буквально.
function M.both_layouts(s)
  local function esc(c)
    if c == "]" or c == "\\" or c == "^" or c == "-" then
      return "\\" .. c
    end
    return c
  end
  local out, i = { "\\V" }, 1
  while i <= #s do
    local c = charat(s, i)
    local p = tr.counterpart(c)
    if p then
      out[#out + 1] = "\\[" .. esc(c) .. esc(p) .. "]"
    else
      out[#out + 1] = c == "\\" and "\\\\" or c
    end
    i = i + #c
  end
  return table.concat(out)
end

-- Исходный текст поиска до `<M-l>` и результат перевода; сбрасываются по CmdlineLeave.
local both = {}

local function toggle_both()
  local cur = vim.fn.getcmdline()
  if both.conv and cur == both.conv then
    vim.fn.setcmdline(both.orig)
    both = {}
  else
    local conv = M.both_layouts(cur)
    both = { orig = cur, conv = conv }
    vim.fn.setcmdline(conv)
  end
end

local function termcodes(s)
  return vim.api.nvim_replace_termcodes(s, true, true, true)
end

-- Выполнить прежнюю привязку клавиши в `c` из expr-привязки модуля. Без прежней
-- привязки — встроенное действие: `<CR>` возвращается как результат, `<Tab>`
-- подаётся как набранная клавиша (флаг t), иначе 'wildchar' не сработает.
local function run_prev(prev, key)
  if not prev then
    if key == "<Tab>" then
      vim.api.nvim_feedkeys(termcodes(key), "nti", false)
      return ""
    end
    return termcodes(key)
  end
  if prev.callback then
    if prev.expr == 1 then
      local r = prev.callback()
      if type(r) ~= "string" then
        return ""
      end
      return prev.replace_keycodes == 1 and termcodes(r) or r
    end
    vim.schedule(prev.callback)
    return ""
  end
  local rhs = prev.rhs or ""
  if prev.expr == 1 then
    rhs = vim.api.nvim_eval(rhs)
  end
  vim.api.nvim_feedkeys(termcodes(rhs), prev.noremap == 1 and "ni" or "mi", false)
  return ""
end

local prev_map = {}

-- Поставить привязку модуля на клавишу key в `c`, запомнив чужую прежнюю.
-- Повторный вызов при своей привязке ничего не меняет.
local function wrap_key(key, desc, fn)
  local m = vim.fn.maparg(key, "c", false, true)
  if m.desc == desc then
    return
  end
  prev_map[key] = (m.lhs and m.buffer ~= 1) and m or nil
  vim.keymap.set("c", key, function()
    local ok, err = pcall(fn)
    if not ok then
      vim.notify("ru-layout: " .. tostring(err), vim.log.levels.ERROR)
    end
    return run_prev(prev_map[key], key)
  end, { expr = true, replace_keycodes = false, desc = desc })
end

-- Перевод текста до курсора перед дополнением.
local function tab_translate()
  if vim.fn.getcmdtype() ~= ":" then
    return
  end
  local line, pos = vim.fn.getcmdline(), vim.fn.getcmdpos()
  local before, after = line:sub(1, pos - 1), line:sub(pos)
  local new = M.translate(before)
  if new ~= before then
    vim.fn.setcmdline(new .. after, #new + 1)
  end
end

local function cr_translate()
  if vim.fn.getcmdtype() ~= ":" then
    return
  end
  local line = vim.fn.getcmdline()
  local new = M.translate(line)
  if new ~= line then
    vim.fn.setcmdline(new)
  end
end

-- `<Tab>` модуля поверх привязки blink.cmp или другой. blink ставит свои привязки
-- в `c` асинхронно после загрузки, поэтому проверка повторяется на CmdlineEnter
-- и после `blink.cmp.keymap.setup`.
function M.ensure_tab()
  wrap_key("<Tab>", DESC_TAB, tab_translate)
end

-- Прежняя привязка клавиши в `c`, поверх которой стоит привязка модуля (для тестов).
function M._prev(key)
  return prev_map[key]
end

local blink_patched = false
local function patch_blink()
  if blink_patched then
    return
  end
  local ok, km = pcall(require, "blink.cmp.keymap")
  if not ok or type(km) ~= "table" or type(km.setup) ~= "function" then
    return
  end
  blink_patched = true
  local orig = km.setup
  km.setup = function(...)
    local r = { orig(...) }
    M.ensure_tab()
    return unpack(r)
  end
end

function M.setup()
  wrap_key("<CR>", DESC_CR, cr_translate)
  M.ensure_tab()
  for _, key in ipairs({ "<M-l>", "<M-д>" }) do
    vim.keymap.set("c", key, function()
      local t = vim.fn.getcmdtype()
      if t == "/" or t == "?" then
        toggle_both()
        -- setcmdline из привязки не обновляет incsearch: вставка и удаление символа
        -- дают изменение строки, после которого подсветка и курсор пересчитываются.
        return "x\8"
      end
      return termcodes(key)
    end, { expr = true, replace_keycodes = false, desc = DESC_BOTH })
  end
  local group = vim.api.nvim_create_augroup("ru-layout-cmdline", { clear = true })
  vim.api.nvim_create_autocmd("CmdlineEnter", { group = group, callback = M.ensure_tab })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      both = {}
    end,
  })
  if package.loaded["blink.cmp"] then
    patch_blink()
  end
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = function(ev)
      if ev.data == "blink.cmp" then
        patch_blink()
      end
    end,
  })
end

return M
