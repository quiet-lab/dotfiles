-- Перевод привязок на русскую раскладку: к привязке с латинским lhs ставится
-- вторая — с тем же rhs, callback и опциями и lhs, переведённым на ЙЦУКЕН
-- (`<leader>ff` → `<leader>аа`, `<M-d>` → `<M-в>`). Приём — подмена функций API
-- привязок: через них идут `vim.keymap.set/del` и `keys` спецификаций lazy.nvim,
-- поэтому `install()` вызывается до `require("lazy").setup`. Привязки, созданные
-- до подмены и командами Vim script (`:nnoremap <buffer>` в vim-fugitive,
-- vim-dadbod-ui), переводят `sweep()` и `sweep_buf()`.
--
-- Правило дубля:
--   n, x, o        — дубль всегда;
--   i, c, t, s     — только при модификаторе в lhs (<M-…>, <A-…>, <C-…>, <D-…>):
--                    буквенные привязки этих режимов (mini.pairs, точки разрыва
--                    отмены) исказили бы русский текст;
--   l              — никогда;
--   v = x + s, "" = n + x + s + o, ! = i + c — правило применяется к каждому режиму.
-- lhs с <Plug> или <SNR> в начале не переводится. Кириллическая привязка, которую
-- поставил не модуль (пользовательская), не перекрывается дублем.
--
-- Независимость от хоста. В русской раскладке хост, передающий сочетания по
-- физической клавише (wezterm), шлёт `<C-w>` и `ч`, а хост, передающий символ
-- (Neovide), — `<C-ц>` и `ч`. Поэтому у lhs с модификатором и буквами дублей два:
-- `<C-w>x` → `<C-ц>ч` и `<C-w>ч`. Обратное направление: у кириллической привязки
-- с модификатором (`<M-в>`, `<C-ц>ч`, поставленной для хоста, передающего символ)
-- ставится дубль с латинским сочетанием (`<M-d>`, `<C-w>ч`), если место свободно.
-- Алиасы модуля chords (`<C-в>` → `<C-d>`) ниже дублей: дубль их перекрывает, после
-- снятия дубля алиас ставится снова.
local tr = require("ru-layout.tr")

local M = {}

local api = vim.api
local orig -- исходные функции API, сохраняются один раз
local augroup

-- Реестр. Область — глобальная (G) или буфер (B[номер]); в области:
--   dup[dk]     = { src = sk, mode = m, lhs = ru } — дубль модуля;
--   src[sk]     = { [dk] = true }                  — дубли источника;
--   foreign[dk] = true                             — чужая кириллическая привязка.
-- Ключ — режим .. "\0" .. lhs в виде кодов клавиш (vim.keycode).
local G
local B

local function new_scope()
  return { dup = {}, src = {}, foreign = {} }
end

local function reset_registry()
  G = new_scope()
  B = {}
end
reset_registry()

local function scope(buf)
  if buf == nil then
    return G
  end
  local s = B[buf]
  if not s then
    s = new_scope()
    B[buf] = s
  end
  return s
end

local function resolve_buf(buf)
  if buf == 0 then
    return api.nvim_get_current_buf()
  end
  return buf
end

-- Режимы, которые покрывает аргумент mode функций API.
local EXPAND = {
  [""] = { "n", "x", "s", "o" },
  ["v"] = { "x", "s" },
  ["!"] = { "i", "c" },
}
local function expand(mode)
  return EXPAND[mode] or { mode }
end

local ALWAYS = { n = true, x = true, o = true }
local WITH_MOD = { i = true, c = true, t = true, s = true }

-- Память переводов: lhs → список форм { ru, коды клавиш ru }: полная (`<C-ц>ч`) и,
-- если отличается, с латинскими сочетаниями (`<C-w>ч`). Коды зависят от mapleader
-- и maplocalleader, поэтому при смене любого из них память сбрасывается.
local memo, memo_leader, memo_local = {}, nil, nil
local function to_ru(lhs)
  local leader, localleader = vim.g.mapleader, vim.g.maplocalleader
  if leader ~= memo_leader or localleader ~= memo_local then
    memo, memo_leader, memo_local = {}, leader, localleader
  end
  local r = memo[lhs]
  if r == nil then
    r = {}
    local full = tr.lhs_to_ru(lhs)
    if full ~= lhs then
      r[1] = { full, vim.keycode(full) }
      local phys = tr.lhs_to_ru(lhs, true)
      if phys ~= lhs and phys ~= full then
        r[2] = { phys, vim.keycode(phys) }
      end
    end
    memo[lhs] = r
  end
  return r
end

local function is_special(lhs)
  local head = lhs:sub(1, 5):lower()
  return head == "<plug" or head == "<snr>"
end

local function has_non_ascii(s)
  return s:find("[\128-\255]") ~= nil
end

local function key(mode, lhs)
  return mode .. "\0" .. vim.keycode(lhs)
end

local NONE = {}

-- Формы перевода lhs ({ ru, коды клавиш ru }), если перевод нужен; иначе пустой список.
local function translatable(lhs)
  if is_special(lhs) or has_non_ascii(lhs) then
    return NONE
  end
  return to_ru(lhs)
end

-- Латинская форма кириллического lhs с модификатором (`<M-в>` → `<M-d>`) и её коды;
-- nil, если в lhs нет сочетаний с кириллицей.
local function reverse_of(lhs)
  if is_special(lhs) or not tr.has_modifier(lhs) then
    return nil
  end
  local us = tr.lhs_mods_to_us(lhs)
  if us == lhs then
    return nil
  end
  return us, vim.keycode(us)
end

-- Модуль chords: восстановление алиаса и признак его привязок, если модуль загружен.
local function chords()
  return package.loaded["ru-layout.chords"]
end
local function restore(m, raw)
  local c = chords()
  if c then
    c.restore(m, raw)
  end
end
local function is_chord(d, m)
  local c = chords()
  return c ~= nil and c.is_ours(d, m)
end

-- Место (режим m, lhs) занято привязкой, которую нельзя перекрыть дублем: не алиасом
-- chords и не дублем модуля.
-- sk — источник ставящегося дубля: свой прежний дубль места не занимает (его rhs
-- обновляется), дубль другого источника занимает.
local function occupied(s, buf, m, lhs, dk, sk)
  if s.dup[dk] then
    return s.dup[dk].src ~= sk
  end
  local d
  if buf then
    d = api.nvim_buf_call(buf, function()
      return vim.fn.maparg(lhs, m, false, true)
    end)
    if d.buffer ~= 1 then
      d = {}
    end
  else
    d = vim.fn.maparg(lhs, m, false, true)
    if d.buffer == 1 then
      d = {}
    end
  end
  return d.lhs ~= nil and not is_chord(d, m)
end

local function allowed(m, lhs)
  return ALWAYS[m] or (WITH_MOD[m] and tr.has_modifier(lhs)) or false
end

local function register(s, sk, dk, m, ru)
  local old = s.dup[dk]
  if old and old.src ~= sk and s.src[old.src] then
    s.src[old.src][dk] = nil
  end
  s.dup[dk] = { src = sk, mode = m, lhs = ru }
  local list = s.src[sk]
  if not list then
    list = {}
    s.src[sk] = list
  end
  list[dk] = true
end

-- Поставленная не модулем кириллическая привязка: дубль на этом месте забывается,
-- привязка помечается чужой и дублем больше не перекрывается.
local function mark_foreign(s, dk)
  local d = s.dup[dk]
  if d then
    if s.src[d.src] then
      s.src[d.src][dk] = nil
    end
    s.dup[dk] = nil
  end
  s.foreign[dk] = true
end

-- Удаление дублей источника sk (после удаления самого источника). На месте снятого
-- глобального дубля ставится алиас chords, если он там был.
local function drop_dups(s, sk, buf)
  local list = s.src[sk]
  if not list then
    return
  end
  for dk in pairs(list) do
    local d = s.dup[dk]
    if d and d.src == sk then
      -- Удаление по кодам клавиш из ключа, а не по d.lhs: `<leader>` и
      -- `<localleader>` в d.lhs раскрылись бы по нынешнему значению переменной,
      -- а дубль поставлен при том, что действовало тогда.
      local lhs = vim.fn.keytrans(dk:sub(#d.mode + 2))
      if buf then
        pcall(orig.buf_del, buf, d.mode, lhs)
      else
        pcall(orig.del, d.mode, lhs)
      end
      s.dup[dk] = nil
      if not buf then
        restore(d.mode, dk:sub(#d.mode + 2))
      end
    end
  end
  s.src[sk] = nil
end

-- Поставить дубль lhs=ru с rhs и opts в режиме m и записать его за источником sk.
local function put_dup(s, buf, m, ru, rawru, rhs, o, sk)
  local ok
  if buf then
    ok = pcall(orig.buf_set, buf, m, ru, rhs, o)
  else
    ok = pcall(orig.set, m, ru, rhs, o)
  end
  if ok then
    register(s, sk, m .. "\0" .. rawru, m, ru)
  end
end

-- Привязка на месте прежнего дубля (дубль перезаписан): дубль забывается.
local function forget_dup(s, k)
  local d = s.dup[k]
  if d then
    if s.src[d.src] then
      s.src[d.src][k] = nil
    end
    s.dup[k] = nil
  end
end

-- Дубли для только что поставленной привязки (buf == nil — глобальная).
local function on_set(buf, mode, lhs, rhs, opts)
  local s = scope(buf)
  local modes = expand(mode)
  local o = opts
  if o and o.unique then
    o = vim.tbl_extend("force", o, { unique = false })
  end
  if has_non_ascii(lhs) then
    for _, m in ipairs(modes) do
      mark_foreign(s, key(m, lhs))
    end
    local us, rawus = reverse_of(lhs)
    if us then
      local sk_raw = vim.keycode(lhs)
      for _, m in ipairs(modes) do
        local dk = m .. "\0" .. rawus
        local sk = m .. "\0" .. sk_raw
        if m ~= "l" and not occupied(s, buf, m, us, dk, sk) then
          put_dup(s, buf, m, us, rawus, rhs, o, sk)
        end
      end
    end
    return
  end
  local raw = vim.keycode(lhs)
  for _, m in ipairs(modes) do
    forget_dup(s, m .. "\0" .. raw)
  end
  local list = translatable(lhs)
  if #list == 0 then
    return
  end
  for _, m in ipairs(modes) do
    if allowed(m, lhs) then
      for _, f in ipairs(list) do
        local dk = m .. "\0" .. f[2]
        if not s.foreign[dk] then
          put_dup(s, buf, m, f[1], f[2], rhs, o, m .. "\0" .. raw)
        end
      end
    end
  end
end

local function on_del(buf, mode, lhs)
  local s = scope(buf)
  for _, m in ipairs(expand(mode)) do
    local k = key(m, lhs)
    if s.dup[k] then
      -- Удалён сам дубль: источник его больше не ведёт.
      local d = s.dup[k]
      if s.src[d.src] then
        s.src[d.src][k] = nil
      end
      s.dup[k] = nil
    end
    local was_foreign = s.foreign[k]
    s.foreign[k] = nil
    drop_dups(s, k, buf)
    if was_foreign and not buf then
      restore(m, vim.keycode(lhs))
    end
  end
end

local function set_keymap(mode, lhs, rhs, opts)
  orig.set(mode, lhs, rhs, opts)
  on_set(nil, mode, lhs, rhs, opts)
end

local function buf_set_keymap(buf, mode, lhs, rhs, opts)
  orig.buf_set(buf, mode, lhs, rhs, opts)
  on_set(resolve_buf(buf), mode, lhs, rhs, opts)
end

local function del_keymap(mode, lhs)
  orig.del(mode, lhs)
  on_del(nil, mode, lhs)
end

local function buf_del_keymap(buf, mode, lhs)
  orig.buf_del(buf, mode, lhs)
  on_del(resolve_buf(buf), mode, lhs)
end

local SWEEP_MODES = { "n", "x", "s", "o", "i", "c", "t" }

-- Проход по списку привязок (nvim_get_keymap/nvim_buf_get_keymap) одного режима.
-- Дубль ставится через mapset(): он сохраняет контекст сценария (sid) привязок
-- Vim script с <SID> и <script> в rhs.
local function sweep_list(s, m, list, buf)
  -- Сначала чужие кириллические привязки, чтобы дубль их не перекрыл, и перечень
  -- существующих: дубль из реестра, снятый мимо API (`:mapclear <buffer>` при
  -- перечитывании буфера плагином), ставится заново.
  local present = {}
  -- Привязки модуля chords (алиасы, чтецы) не чужие и не переводятся.
  local own = {}
  for _, e in ipairs(list) do
    if is_chord(e, m) then
      own[e] = true
    else
      present[m .. "\0" .. e.lhsraw] = true
    end
  end
  local foreign = {}
  for _, e in ipairs(list) do
    if not own[e] and has_non_ascii(e.lhs) then
      local dk = m .. "\0" .. e.lhsraw
      if not s.dup[dk] then
        s.foreign[dk] = true
        foreign[#foreign + 1] = e
      end
    end
  end
  -- Словарь привязки меняется на месте: формы перевода и ключ источника берутся
  -- до первой подстановки, а список после прохода не нужен.
  local function put(e, sk, ru, rawru)
    e.lhs = ru
    e.lhsraw = rawru
    e.lhsrawalt = nil
    e.mode = m
    local ok
    if buf then
      ok = pcall(api.nvim_buf_call, buf, function()
        vim.fn.mapset(m, false, e)
      end)
    else
      ok = pcall(vim.fn.mapset, m, false, e)
    end
    if ok then
      register(s, sk, m .. "\0" .. rawru, m, ru)
    end
  end
  -- Обратные дубли чужих кириллических привязок: lhs и коды — до подстановок.
  local rev = {}
  for _, e in ipairs(foreign) do
    local us, rawus = reverse_of(e.lhs)
    if us then
      rev[#rev + 1] = { e, m .. "\0" .. e.lhsraw, us, rawus }
    end
  end
  for _, e in ipairs(list) do
    if not own[e] and allowed(m, e.lhs) then
      local sk = m .. "\0" .. e.lhsraw
      for _, f in ipairs(translatable(e.lhs)) do
        local dk = m .. "\0" .. f[2]
        local d = s.dup[dk]
        if not s.foreign[dk] and not (d and d.src == sk and present[dk]) then
          put(e, sk, f[1], f[2])
        end
      end
    end
  end
  -- Обратные дубли чужих кириллических привязок с модификатором.
  for _, r in ipairs(rev) do
    local e, sk, us, rawus = r[1], r[2], r[3], r[4]
    local dk = m .. "\0" .. rawus
    local d = s.dup[dk]
    -- Место занято чужой привязкой или дублем другого источника — как в on_set.
    if not (d and present[dk]) and not (present[dk] and not d) then
      put(e, sk, us, rawus)
    end
  end
end

-- Дубли для уже существующих глобальных привязок всех режимов, у которых их нет.
function M.sweep()
  for _, m in ipairs(SWEEP_MODES) do
    sweep_list(G, m, api.nvim_get_keymap(m), nil)
  end
end

-- То же для буферных привязок буфера buf (0 — текущий).
function M.sweep_buf(buf)
  buf = resolve_buf(buf or 0)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  local s = scope(buf)
  for _, m in ipairs(SWEEP_MODES) do
    sweep_list(s, m, api.nvim_buf_get_keymap(buf, m), buf)
  end
end

-- Типы файлов Vim-script плагинов, ставящих буферные привязки командами
-- `:nnoremap <buffer>` мимо API.
M.filetypes = { "fugitive", "fugitiveblame", "git", "dbui", "dbout", "sql" }

function M.installed()
  return orig ~= nil
end

-- Занятые места глобальных привязок для алиасов chords: режим → { [коды lhs] = true }
-- по дублям и чужим кириллическим привязкам реестра.
function M.taken()
  local t = {}
  for _, tbl in ipairs({ G.dup, G.foreign }) do
    for k in pairs(tbl) do
      local m, raw = k:match("^(%a)%z(.*)$")
      if m then
        t[m] = t[m] or {}
        t[m][raw] = true
      end
    end
  end
  return t
end

-- Установка привязки мимо подмены (без дублей): для алиасов модуля chords.
function M.raw_set(mode, lhs, rhs, opts)
  return (orig and orig.set or api.nvim_set_keymap)(mode, lhs, rhs, opts)
end

-- Подмена функций API привязок и автокоманды прохода по буферным привязкам.
-- Повторный вызов ничего не меняет.
function M.install()
  if orig then
    return
  end
  orig = {
    set = api.nvim_set_keymap,
    buf_set = api.nvim_buf_set_keymap,
    del = api.nvim_del_keymap,
    buf_del = api.nvim_buf_del_keymap,
  }
  api.nvim_set_keymap = set_keymap
  api.nvim_buf_set_keymap = buf_set_keymap
  api.nvim_del_keymap = del_keymap
  api.nvim_buf_del_keymap = buf_del_keymap

  augroup = api.nvim_create_augroup("ru-layout.keymap", { clear = true })
  -- vim-fugitive ставит буферные привязки до FileType и в своём обработчике
  -- FileType, vim-dadbod-ui — после FileType тем же вызовом; поэтому проход идёт
  -- в vim.schedule после FileType — по завершении текущей обработки событий, без
  -- срока. Запасной BufWinEnter у буферов тех же типов переводит привязки,
  -- появившиеся позже (буфер, перечитанный плагином, `:mapclear <buffer>`).
  api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = M.filetypes,
    desc = "ru-layout: дубли буферных привязок Vim-script плагинов",
    callback = function(args)
      vim.schedule(function()
        M.sweep_buf(args.buf)
      end)
    end,
  })
  api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    desc = "ru-layout: дубли буферных привязок, поставленных мимо API",
    callback = function(args)
      if vim.tbl_contains(M.filetypes, vim.bo[args.buf].filetype) then
        M.sweep_buf(args.buf)
      end
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    desc = "ru-layout: забыть реестр дублей буфера",
    callback = function(args)
      B[args.buf] = nil
    end,
  })
end

-- Вернуть исходные функции API (для тестов); дубли остаются.
function M.uninstall()
  if not orig then
    return
  end
  api.nvim_set_keymap = orig.set
  api.nvim_buf_set_keymap = orig.buf_set
  api.nvim_del_keymap = orig.del
  api.nvim_buf_del_keymap = orig.buf_del
  orig = nil
  pcall(api.nvim_del_augroup_by_id, augroup)
  reset_registry()
end

-- Сведения для тестов: число дублей и чужих кириллических привязок в области.
function M.stats(buf)
  local s = buf and B[resolve_buf(buf)] or (not buf and G) or new_scope()
  local nd, nf = 0, 0
  for _ in pairs(s.dup) do
    nd = nd + 1
  end
  for _ in pairs(s.foreign) do
    nf = nf + 1
  end
  return { dups = nd, foreign = nf }
end

return M
