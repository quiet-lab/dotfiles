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

-- Память переводов: lhs → { ru, коды клавиш ru }. Коды зависят от mapleader
-- и maplocalleader, поэтому при смене любого из них память сбрасывается.
local memo, memo_leader, memo_local = {}, nil, nil
local function to_ru(lhs)
  local leader, localleader = vim.g.mapleader, vim.g.maplocalleader
  if leader ~= memo_leader or localleader ~= memo_local then
    memo, memo_leader, memo_local = {}, leader, localleader
  end
  local r = memo[lhs]
  if r == nil then
    local ru = tr.lhs_to_ru(lhs)
    r = { ru, ru ~= lhs and vim.keycode(ru) or nil }
    memo[lhs] = r
  end
  return r[1], r[2]
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

-- Перевод lhs и его коды клавиш, если перевод нужен; иначе nil.
local function translatable(lhs)
  if is_special(lhs) or has_non_ascii(lhs) then
    return nil
  end
  local ru, rawru = to_ru(lhs)
  if ru == lhs then
    return nil
  end
  return ru, rawru
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

-- Удаление дублей источника sk (после удаления самого источника).
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
    end
  end
  s.src[sk] = nil
end

-- Дубли для только что поставленной привязки (buf == nil — глобальная).
local function on_set(buf, mode, lhs, rhs, opts)
  local s = scope(buf)
  local modes = expand(mode)
  if has_non_ascii(lhs) then
    for _, m in ipairs(modes) do
      mark_foreign(s, key(m, lhs))
    end
    return
  end
  local ru, rawru = translatable(lhs)
  if not ru then
    return
  end
  local o = opts
  if o and o.unique then
    o = vim.tbl_extend("force", o, { unique = false })
  end
  local raw = vim.keycode(lhs)
  for _, m in ipairs(modes) do
    if allowed(m, lhs) then
      local dk = m .. "\0" .. rawru
      if not s.foreign[dk] then
        local ok
        if buf then
          ok = pcall(orig.buf_set, buf, m, ru, rhs, o)
        else
          ok = pcall(orig.set, m, ru, rhs, o)
        end
        if ok then
          register(s, m .. "\0" .. raw, dk, m, ru)
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
    s.foreign[k] = nil
    drop_dups(s, k, buf)
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
  for _, e in ipairs(list) do
    if has_non_ascii(e.lhs) then
      local dk = m .. "\0" .. e.lhsraw
      present[dk] = true
      if not s.dup[dk] then
        s.foreign[dk] = true
      end
    end
  end
  for _, e in ipairs(list) do
    local lhs = e.lhs
    local ru, rawru
    if allowed(m, lhs) then
      ru, rawru = translatable(lhs)
    end
    if ru then
      local sk = m .. "\0" .. e.lhsraw
      local dk = m .. "\0" .. rawru
      local d = s.dup[dk]
      if not s.foreign[dk] and not (d and d.src == sk and present[dk]) then
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
          register(s, sk, dk, m, ru)
        end
      end
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
