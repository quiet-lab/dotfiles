-- Сочетания с Ctrl и Alt независимо от хоста. Терминал, кодирующий клавиши по
-- физическому положению (wezterm), передаёт Ctrl+`в` как `<C-d>`, хост, передающий
-- символ (Neovide), — как `<C-в>`. Модуль делает обе формы равноправными по
-- построению, хост не определяется:
--
--   * алиасы: `<C-кир>` → `<C-лат>` (заглавная — `<C-S-В>` → `<C-S-d>`) во всех
--     режимах, с переназначением (remap): сочетание приходит к той же привязке или
--     встроенной команде, что латинское; в `:` `<C-х>` (это `<C-[>`, Esc) — `<C-c>`:
--     Esc из привязки выполнил бы командную строку. `<M-кир>` — только в terminal:
--     в остальных режимах непривязанное `<M-в>` уже равно `<Esc>в`, то есть по
--     langmap `<Esc>d`, как `<M-d>`; алиас сломал бы эту замену;
--   * чтецы: у сочетаний, после которых Neovim читает следующую клавишу мимо
--     привязок (`<C-r>{регистр}`, `<C-x>{режим}`, `<C-g>{буква}`, `<C-v>{символ}`,
--     `<C-\>{…}`, `<C-w>{…}`), следующая клавиша читается привязкой-выражением и
--     переводится по перечню `ru-layout.index`;
--   * явные сочетания для записей index.txt, где клавиша с Ctrl вторая после
--     буквы (`g<C-a>`, `]<C-d>`): `g<C-ф>`, `п<C-ф>` → `g<C-a>`.
--
-- Приоритет модуля ниже любой другой привязки: чужая привязка на том же месте не
-- перезаписывается, а дубль модуля keymap перекрывает алиас; после снятия дубля или
-- чужой кириллической привязки алиас ставится снова (`restore`).
local tr = require("ru-layout.tr")
local INDEX = require("ru-layout.index")

local M = {}

local api = vim.api
local kc = vim.keycode

-- Признак привязок модуля в desc: keymap.sweep() не считает их чужими.
M.DESC = "ru-layout chord"

-- Группы режимов: один вызов API на группу.
local GROUPS = { [""] = { "n", "x", "s", "o" }, ["!"] = { "i", "c" }, t = { "t" } }
local ALL_MODES = { "n", "x", "s", "o", "i", "c", "t" }

-- Записи index.txt для режима: select пользуется записями visual, o — normal
-- (продолжение `<C-\>` в o и s index.txt не перечисляет отдельно).
local INDEX_MODE = { n = "n", x = "x", s = "x", o = "n", i = "i", c = "c", t = "t" }

-- Чтецы: латинский префикс, режимы, нужен ли чтец на латинском префиксе, чьи
-- записи index.txt продолжают префикс (as — другой префикс, index — другой режим).
-- На кириллическом префиксе чтец нужен всегда: Neovim читает вторую клавишу без
-- привязок, алиас к ней не применяется. На латинском — там, где вторая клавиша и при
-- физическом кодировании приходит кириллицей и встроенная команда её не переводит:
-- имя регистра в `:` (`langmap` в командной строке не действует), буква после
-- `<C-x>` и `<C-g>` в insert, клавиша после `<C-\>` (у `\` нет кириллической формы).
-- В insert имя регистра после `<C-r>` переводит langmap, `<C-w>` в normal переводит
-- букву по langmap сам.
M.READERS = {
  { key = "<C-r>", modes = { "i" }, latin = false },
  { key = "<C-r>", modes = { "c" }, latin = true },
  { key = "<C-x>", modes = { "i" }, latin = true },
  { key = "<C-g>", modes = { "i" }, latin = true },
  { key = "<C-v>", modes = { "i", "c" }, latin = false },
  { key = "<C-q>", modes = { "i", "c" }, latin = false, as = "<C-v>" },
  { key = "<C-w>", modes = { "n", "x" }, latin = false, index = "n" },
  { key = "<C-\\>", modes = { "n", "x", "s", "o", "i", "c" }, latin = true },
}

-- Допустимые имена регистров (`:h registers`).
local REGISTERS = [["0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-*+.:%#/=_]]

-- Пары (латинский символ, кириллический) из таблицы раскладки: только кириллица и
-- другие не-ASCII символы ru (ASCII-знаки ru ведёт модуль punct).
local function letter_pairs()
  local out = {}
  for us, ru in pairs(tr.us2ru) do
    if #ru > 1 then
      out[#out + 1] = { us, ru }
    end
  end
  table.sort(out, function(a, b)
    return a[1] < b[1]
  end)
  return out
end

-- Заглавные символы ru: второй уровень клавиши в таблице раскладки (без vim.fn в
-- цикле установки).
local UPPER = {}
for _, k in ipairs(require("ru-layout.table").keys) do
  if k.level == 2 then
    UPPER[k.ru] = true
  end
end

-- Формы сочетаний символа ru: { lhs, латинский rhs, только terminal }. Строчная
-- буква — `<C-в>` и `<M-в>`; заглавная — `<C-S-В>` и `<M-В>`: так их передаёт хост,
-- передающий символ (Shift+в приходит как `В`, Alt+Shift+в — как `<M-В>`).
local function forms(ru)
  local is_upper = UPPER[ru] == true
  local out = {}
  for _, m in ipairs(is_upper and { "C-S-", "M-" } or { "C-", "M-" }) do
    local us = tr.mod_to_us(m, ru)
    if us then
      out[#out + 1] = { "<" .. m .. ru .. ">", us, m == "M-" }
    end
  end
  return out
end
M.forms = forms

-- rhs алиаса в режиме: в `:` Esc из привязки выполнил бы строку, поэтому `<C-c>`.
local ESC = kc("<Esc>")
local function mode_rhs(us, m)
  if m == "c" and kc(us) == ESC then
    return "<C-c>"
  end
  return us
end

-- Сведения о поставленных чтецах и явных сочетаниях: spec[режим][коды lhs] =
-- { lhs, rhs, opts } — для restore и признака привязки модуля. Алиасы не
-- записываются: их rhs выводится из lhs (alias_rhs), это дешевле при запуске.
local spec = {}
M.spec = spec

local function remember(mode, lhs, rhs, opts)
  spec[mode] = spec[mode] or {}
  spec[mode][kc(lhs)] = { lhs = lhs, rhs = rhs, opts = opts }
end

-- Функция установки: исходная из keymap (мимо подмены, без дублей) или API.
local function raw_set(mode, lhs, rhs, opts)
  local ok, keymap = pcall(require, "ru-layout.keymap")
  local f = ok and keymap.raw_set or api.nvim_set_keymap
  return pcall(f, mode, lhs, rhs, opts)
end

-- Занятые места глобальных привязок по режимам: дубли и чужие кириллические
-- привязки из реестра модуля keymap, в записи keytrans (`<C-в>`). Берутся только
-- короткие lhs, начинающиеся со специальной клавиши: алиасы — одно сочетание, явные
-- сочетания — две клавиши. Привязки вне реестра защищает `<unique>`.
local function taken()
  local ok, keymap = pcall(require, "ru-layout.keymap")
  local raw = ok and keymap.taken and keymap.taken() or {}
  local t = {}
  for _, m in ipairs(ALL_MODES) do
    t[m] = {}
    for k in pairs(raw[m] or {}) do
      if #k <= 12 then
        t[m][vim.fn.keytrans(k)] = true
      end
    end
  end
  return t
end

-- rhs алиаса для lhs (запись keytrans) в режиме m; nil, если там нет алиаса модуля.
local function alias_rhs(lhs, m)
  local mods, c = tr.split_mod(lhs)
  if not mods then
    return nil
  end
  for _, f in ipairs(forms(c)) do
    if f[1] == lhs and (m == "t" or not f[3]) then
      return mode_rhs(f[2], m)
    end
  end
  return nil
end
M.alias_rhs = alias_rhs

-- Команда :map режима или группы.
local MAPCMD = { [""] = "map", ["!"] = "map!", t = "tmap", n = "nmap", x = "xmap", s = "smap", o = "omap" }
MAPCMD.i, MAPCMD.c = "imap", "cmap"
local NOREMAPCMD = { n = "nnoremap", x = "xnoremap" }

-- Сравнение лексемы перечня с прочитанной клавишей — по кодам клавиш.
local function token_raw(t)
  if t == "<" then
    return "<"
  end
  return kc(t)
end

local function is_arg(t)
  return t:sub(1, 1) == "{" and #t > 2
end

-- Записи режима (имя в INDEX), которые начинаются с префикса prefix (список кодов
-- клавиш).
local function candidates(imode, prefix)
  local out = {}
  for _, e in ipairs(INDEX[imode] or {}) do
    if #e > #prefix then
      local ok = true
      for i, raw in ipairs(prefix) do
        local t = e[i]
        if not is_arg(t) and token_raw(t) ~= raw then
          ok = false
          break
        end
      end
      if ok then
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- Читать ли следующую клавишу: на позиции pos есть конкретная клавиша или аргумент,
-- который переводится (регистр, буквальный символ). Текстовые аргументы (`{expr}`,
-- `{mode}`, `{char1}` диграфа) читает сама встроенная команда: она показывает
-- приглашение и дополнение.
local READ_ARGS = { ["{register}"] = true, ["{regname}"] = true, ["{char}"] = true, ["{number}"] = true }
local function wants_more(cands, pos)
  for _, e in ipairs(cands) do
    local t = e[pos]
    if not is_arg(t) or READ_ARGS[t] then
      return true
    end
  end
  return false
end

-- Выбор формы прочитанной клавиши c для позиции pos среди записей cands: точная
-- латинская лексема, иначе аргумент. Возвращает клавишу и признак конца.
local function accept(cands, pos, c)
  local us_mod = tr.key_to_us(c) -- только сочетание с модификатором
  local us_all = tr.key_to_us(c, true) -- и буква без модификатора
  local args = {}
  for _, e in ipairs(cands) do
    local t = e[pos]
    if is_arg(t) then
      args[t] = true
    else
      local raw = token_raw(t)
      if raw == c or raw == us_mod or raw == us_all then
        return raw, false
      end
    end
  end
  if args["{register}"] or args["{regname}"] then
    if REGISTERS:find(us_all, 1, true) and #us_all == 1 then
      return us_all, true
    end
    return c, true
  end
  if args["{char}"] or args["{number}"] then
    -- Буквальный ввод: кириллица — текст, переводится только сочетание.
    return us_mod, true
  end
  return c, true
end

local CTRL_C = kc("<C-c>")

-- Чтец для латинского префикса key в режиме mode: функция привязки-выражения.
-- Продолжения берутся у записей префикса as (`<C-q>` — как `<C-v>`) режима imode.
local function reader(mode, key, as, imode)
  local head, look = kc(key), kc(as or key)
  imode = imode or INDEX_MODE[mode]
  return function()
    local seq = { look }
    while true do
      local cands = candidates(imode, seq)
      if not wants_more(cands, #seq + 1) then
        break
      end
      local ok, c = pcall(vim.fn.getcharstr)
      if not ok then
        return ""
      end
      -- `<C-c>`, набранная латиницей, прерывает getcharstr (ok == false); та же
      -- клавиша в кириллической форме приходит обычной клавишей — тоже отмена.
      if tr.key_to_us(c) == CTRL_C then
        return ""
      end
      local got, final = accept(cands, #seq + 1, c)
      seq[#seq + 1] = got
      if final then
        break
      end
    end
    seq[1] = head
    return table.concat(seq)
  end
end
M.reader = reader

-- Сочетания разбора: в записи с Ctrl не на первом месте все клавиши Ctrl получают
-- кириллическую форму (хотя бы одна), буквы без модификатора — обе формы.
local function sequence_forms(e)
  local variants = { { "" } }
  local function extend(opts)
    local nv = {}
    for _, v in ipairs(variants) do
      for _, o in ipairs(opts) do
        nv[#nv + 1] = { v[1] .. o[1], (v[2] or false) or o[2] }
      end
    end
    variants = nv
  end
  for _, t in ipairs(e) do
    if is_arg(t) then
      return {}
    end
    local mods, c = tr.split_mod(t)
    local ru = mods and tr.us2ru[c]
    if ru and #ru > 1 then
      extend({ { t, false }, { "<" .. mods .. ru .. ">", true } })
    elseif #t == 1 and tr.us2ru[t] and #tr.us2ru[t] > 1 then
      extend({ { t == "<" and "<lt>" or t, false }, { tr.us2ru[t], false } })
    else
      extend({ { t == "<" and "<lt>" or t, false } })
    end
  end
  local out = {}
  for _, v in ipairs(variants) do
    if v[2] then
      out[#out + 1] = v[1]
    end
  end
  return out
end
M.sequence_forms = sequence_forms

local function opts_for(desc, extra)
  local o = { desc = M.DESC .. ": " .. desc }
  for k, v in pairs(extra or {}) do
    o[k] = v
  end
  return o
end

-- Установка всех алиасов, чтецов и явных сочетаний. Места, занятые дублями и чужими
-- привязками, пропускаются; алиасы и явные сочетания ставятся одним пакетом команд
-- `:map <unique>` (через API в несколько раз дольше, а это время запуска Neovim).
-- Вызывается после keymap.sweep(): проход по привязкам не видит алиасов.
function M.setup()
  local busy = taken()
  local readers = {}
  for _, r in ipairs(M.READERS) do
    for _, m in ipairs(r.modes) do
      readers[m] = readers[m] or {}
      readers[m][r.key] = r
    end
  end
  local lines = {}
  local function add(cmd, lhs, rhs)
    lines[#lines + 1] = ("silent! %s <unique> %s %s"):format(cmd, lhs, rhs)
  end
  local function set_reader(m, lhs, r)
    if not busy[m][lhs] then
      local o = opts_for(r.key, {
        expr = true,
        replace_keycodes = false,
        callback = reader(m, r.key, r.as, r.index),
      })
      raw_set(m, lhs, "", o)
      remember(m, lhs, "", o)
    end
  end

  -- Алиасы: режимы группы, где у lhs один и тот же rhs и нет чтеца, ставятся одной
  -- командой группы, остальные — командами режимов.
  for _, p in ipairs(letter_pairs()) do
    for _, f in ipairs(forms(p[2])) do
      local lhs, us, term_only = f[1], f[2], f[3]
      for group, modes in pairs(GROUPS) do
        if group == "t" or not term_only then
          local plain, all = {}, true
          for _, m in ipairs(modes) do
            if readers[m] and readers[m][us] then
              all = false
              set_reader(m, lhs, readers[m][us])
            elseif busy[m][lhs] then
              all = false
            else
              plain[#plain + 1] = m
              if mode_rhs(us, m) ~= us then
                all = false
              end
            end
          end
          if all then
            add(MAPCMD[group], lhs, us)
          else
            for _, m in ipairs(plain) do
              add(MAPCMD[m], lhs, mode_rhs(us, m))
            end
          end
        end
      end
    end
  end

  -- Чтецы на латинских префиксах.
  for _, r in ipairs(M.READERS) do
    if r.latin then
      for _, m in ipairs(r.modes) do
        set_reader(m, r.key, r)
      end
    end
  end

  -- Явные сочетания: записи, где Ctrl не первая клавиша (`g<C-a>`, `]<C-d>`).
  for _, m in ipairs({ "n", "x" }) do
    for _, e in ipairs(INDEX[m]) do
      if not e[1]:find("^<C%-") then
        local rhs = table.concat(vim.tbl_map(function(t)
          return t == "<" and "<lt>" or t
        end, e))
        for _, lhs in ipairs(sequence_forms(e)) do
          if not busy[m][lhs] then
            add(NOREMAPCMD[m], lhs, rhs)
            remember(m, lhs, rhs, { noremap = true })
          end
        end
      end
    end
  end
  api.nvim_exec2(table.concat(lines, "\n"), {})
end

-- Привязка модуля на месте (режим, коды lhs) снята дублем или чужой привязкой, а
-- теперь место свободно: поставить её снова.
function M.restore(mode, raw)
  local s = spec[mode] and spec[mode][raw]
  if not s then
    local lhs = vim.fn.keytrans(raw)
    local us = alias_rhs(lhs, mode)
    if not us then
      return
    end
    s = { lhs = lhs, rhs = us, opts = {} }
  end
  if vim.fn.maparg(s.lhs, mode) ~= "" then
    return
  end
  raw_set(mode, s.lhs, s.rhs, s.opts)
end

-- Привязка модуля ли это: d — словарь maparg()/nvim_get_keymap(), m — режим.
-- Чтецы узнаются по описанию; алиасы и явные сочетания (у :map описания нет) — по
-- lhs и rhs: rhs совпадает с тем, что модуль ставит на этом месте.
function M.is_ours(d, m)
  if type(d) ~= "table" or not d.lhs or type(d.rhs) ~= "string" then
    return false
  end
  if type(d.desc) == "string" and d.desc:sub(1, #M.DESC) == M.DESC then
    return true
  end
  local raw = d.lhsraw or kc(d.lhs)
  local s = spec[m] and spec[m][raw]
  local rhs = s and s.rhs or alias_rhs(vim.fn.keytrans(raw), m)
  return rhs ~= nil and rhs ~= "" and kc(d.rhs) == kc(rhs)
end

return M
