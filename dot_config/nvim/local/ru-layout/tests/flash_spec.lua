-- Модуль ru-layout.flash: метки по раскладке двойника Hyprland, поиск по обеим
-- раскладкам, char, treesitter, remote, `/`, защита от изменений внутренностей flash.
-- Запуск: cd <корень плагина> && nvim -l tests/flash_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

local TEXT = {
  "Привет, это пример русского текста для проверки прыжков по меткам.",
  "Программа проверяет, правильно ли работает поиск при русской раскладке.",
  "Просто пробуем прыгнуть к слову правка, потом к слову проект и прочее.",
  "Каждый абзац содержит повторяющиеся слова: проверка, прыжок, пример, правило.",
  "Пользователь пишет текст, программа предлагает метки, пользователь выбирает метку.",
  "Прямо сейчас проверяем, как метки выглядят при вводе приставки пр в поиске.",
  "Последняя строка: просьба проверить, применимы ли метки в обеих раскладках.",
  "local function sample(x) return x + 1 end",
}
local CODE = {
  "local function select_item(items, index)",
  "  local selected = items[index]",
  "  if selected then return selected.value end",
  "  return nil",
  "end",
}
local LABELS_RU = "фывапролдйцукенгшщзячсмить"

-- Испытуемый: дубли keymap, привязки LazyVim (editor.lua, spec folke/flash.nvim),
-- flash.setup({}), ru-layout.flash.setup(). hypr — ждать раскладку двойника.
local SETUP = [[
local hypr = ...
require("ru-layout.keymap").install()
local layout = require("ru-layout.layout")
layout.setup()
if hypr then
  -- ожидание первого состояния раскладки от двойника: до события сокета
  vim.wait(2 ^ 31 - 1, function() return layout.get() ~= nil end, 1)
end
local map = vim.keymap.set
map({ "n", "x", "o" }, "s", function() require("flash").jump() end, { desc = "Flash" })
map({ "n", "o", "x" }, "S", function() require("flash").treesitter() end, { desc = "Flash Treesitter" })
map("o", "r", function() require("flash").remote() end, { desc = "Remote Flash" })
map({ "o", "x" }, "R", function() require("flash").treesitter_search() end, { desc = "Treesitter Search" })
map("c", "<c-s>", function() require("flash").toggle() end, { desc = "Toggle Flash Search" })
require("flash").setup({})
_G.RUF = require("ru-layout.flash")
_G.RUF_OK = RUF.setup()
_G.FS = require("flashsnap")
]]

local function snap(k)
  return D.lua("return FS.snap(...)", k)
end
local function brief(s)
  return D.lua("return FS.brief(...)", s, 40)
end
local function esc()
  D.input("<Esc>")
  D.sync()
end
local function at(s)
  return ("%s@%d:%d"):format(s.word_at_cursor, s.cursor[1], s.cursor[2])
end
local function mw(m)
  return ("%s@%d:%d"):format(m.word, m.row, m.col)
end
local function find_label(s, pred)
  for _, m in ipairs(s.labeled or {}) do
    if pred(m) then
      return m
    end
  end
end
local function word(w)
  return function(m)
    return m.word == w
  end
end
local function used(s)
  return table.concat(
    vim.tbl_map(function(m)
      return m.label
    end, s.labeled or {}),
    ""
  )
end
local function char_reset()
  D.lua("require('flash.plugins.char').state = nil")
end
-- Выбор метки у слова w: строка таблицы, ожидание — прыжок к началу совпадения.
local function pick(name, s, w, want_label)
  local m = find_label(s, word(w))
  if not m then
    D.row(name, w, want_label or "метка", "метки у «" .. w .. "» нет: " .. brief(s), false)
    esc()
    return
  end
  D.input(m.label)
  D.sync()
  local a = snap()
  D.row(
    name,
    m.label,
    (want_label or m.label) .. " → " .. mw(m),
    m.label .. " → " .. at(a),
    (want_label == nil or m.label == want_label) and a.cursor[1] == m.row and a.cursor[2] == m.col
  )
end

-- ===================== Экземпляр 1: двойник Hyprland, раскладка ru =====================
D.start({ langmap = true, hypr = "ru", plugins = { "flash.nvim" } })
D.lua(SETUP, true)
D.check("setup: обёртки установлены", true, D.lua("return RUF_OK"))
D.check("keymap: дубль ы для s", true, D.lua("return vim.fn.maparg('ы', 'n') ~= ''"))
D.check("keymap: дубль а для f (flash char)", true, D.lua("return vim.fn.maparg('а', 'n') ~= ''"))
D.check("keymap: дубль ж для ;", true, D.lua("return vim.fn.maparg('ж', 'n') ~= ''"))
D.check("layout: ru от двойника", "ru", D.lua("return require('ru-layout.layout').get()"))

-- 4e основной сценарий в ru: ы → пр → кириллическая метка → «правка»
D.reset(TEXT)
D.input("ыпр")
D.sync()
local s1 = snap()
D.row(
  "4e RU: ы + пр",
  "ыпр",
  ("видим, search=\\V\\[пg]\\[рh], 24, labels=%s"):format(LABELS_RU),
  ("видим=%s, search=%s, %d, labels=%s"):format(tostring(s1.visible), s1.search, s1.nresults, s1.labels),
  s1.visible == true and s1.search == "\\V\\[пg]\\[рh]" and s1.nresults == 24 and s1.labels == LABELS_RU
)
D.row(
  "4e RU: метки без продолжений а о е ы и",
  "ыпр",
  "ф:пример … к:правка н:проект",
  brief(s1),
  brief(s1):find("^ф:пример@1:21 р:проверки@1:71 в:прыжков@1:88") ~= nil
)
pick("4e RU: метка к → «правка»", s1, "правка", "к")

-- Пропуск меток: исходный Labeler.skip не вызывается ни разу, наш — по разу на
-- каждое обновление меток (ввод «ыпр»: пустой шаблон, «п», «пр» — одно окно).
D.reset(TEXT)
D.lua([[
local Labeler = require("flash.labeler")
_G.SKIPN = { orig = 0, ours = 0, updates = 0 }
_G.SKIP_SAVED = { skip = Labeler.skip, ours = RUF.skip, update = Labeler.update }
Labeler.skip = function(...) SKIPN.orig = SKIPN.orig + 1; return SKIP_SAVED.skip(...) end
RUF.skip = function(...) SKIPN.ours = SKIPN.ours + 1; return SKIP_SAVED.ours(...) end
Labeler.update = function(...) SKIPN.updates = SKIPN.updates + 1; return SKIP_SAVED.update(...) end
]])
D.input("ыпр")
D.sync()
D.check(
  "labeler: исходный skip не вызывается, наш — по разу на обновление",
  true,
  D.lua([[
local Labeler = require("flash.labeler")
Labeler.skip, RUF.skip, Labeler.update = SKIP_SAVED.skip, SKIP_SAVED.ours, SKIP_SAVED.update
return SKIPN.orig == 0 and SKIPN.updates > 0 and SKIPN.ours == SKIPN.updates or SKIPN]])
)
esc()

-- латинская s в ru: те же кириллические метки
D.reset(TEXT)
D.input("sпр")
D.sync()
local s1b = snap()
D.row(
  "RU: латинская s + пр — метки кириллические",
  "sпр",
  LABELS_RU,
  s1b.labels,
  s1b.labels == LABELS_RU
)
pick("RU: s + пр + метка к → «правка»", s1b, "правка", "к")

-- Backspace в строке поиска flash удаляет символ, а не байт
D.reset(TEXT)
D.input("ыпр<BS>")
D.sync()
local sbs = snap()
D.row(
  "RU: ыпр<BS> — удалён символ",
  "ыпр<BS>",
  "pattern=п, search=\\V\\[пg]",
  ("pattern=%s, search=%s"):format(sbs.pattern, sbs.search),
  sbs.pattern == "п" and sbs.search == "\\V\\[пg]"
)
D.input("р")
D.sync()
local sbs2 = snap()
pick("RU: ыпр<BS>р + метка к → «правка»", sbs2, "правка", "к")

-- 4e обратный сценарий в us
D.hypr_switch("us")
D.check("layout: us после switchxkblayout", "us", D.lua("return require('ru-layout.layout').get()"))
D.reset(TEXT)
D.input("sпр")
D.sync()
local s2 = snap()
D.row(
  "4e US: s + пр — метки латинские",
  "sпр",
  "asdfghjkl…",
  s2.labels:sub(1, 9),
  s2.labels:sub(1, 26) == "asdfghjklqwertyuiopzxcvbnm"
)
pick("4e US: s + пр + метка y → «проект»", s2, "проект", "y")

-- 4b поиск по обеим раскладкам
D.hypr_switch("ru")
D.reset(CODE)
D.input("ыыуд")
D.sync()
local s3 = snap()
D.row(
  "4b RU, код: ы + ыуд (sel набран в ru)",
  "ыыуд",
  "pattern=ыуд, search=\\V\\[ыs]\\[уe]\\[дl], 4, ф:select@1:15 в:selected@2:8 п:selected@3:5 р:selected@3:26",
  ("pattern=%s, search=%s, %d, %s"):format(s3.pattern, s3.search, s3.nresults, brief(s3)),
  s3.pattern == "ыуд"
    and s3.search == "\\V\\[ыs]\\[уe]\\[дl]"
    and s3.nresults == 4
    and brief(s3) == "ф:select@1:15 в:selected@2:8 п:selected@3:5 р:selected@3:26"
)
D.row(
  "4b пропуск меток по паре: после sel идёт e — метки у нет",
  "ыыуд",
  "фвпр",
  used(s3),
  used(s3) == "фвпр"
)
local t3 = s3.labeled[#s3.labeled]
D.input(t3.label)
D.sync()
local a3 = snap()
D.row("4b RU, код: метка р → selected@3:26", "р", "selected@3:26", at(a3), at(a3) == "selected@3:26")

D.hypr_switch("us")
D.reset(TEXT)
D.input("sgh")
D.sync()
local s4 = snap()
D.row(
  "4b US, русский текст: s + gh (клавиши п р)",
  "sgh",
  "search=\\V\\[gп]\\[hр], 24",
  ("search=%s, %d"):format(s4.search, s4.nresults),
  s4.search == "\\V\\[gп]\\[hр]" and s4.nresults == 24
)
esc()

D.hypr_switch("ru")
D.reset(CODE)
D.input("ыыудусе")
D.sync()
local s5 = snap()
D.row(
  "4b RU: ыыудусе (select)",
  "ыыудусе",
  "pattern=ыудусе, 4, метки фвпр",
  ("pattern=%s, %d, метки %s"):format(s5.pattern, s5.nresults, used(s5)),
  s5.pattern == "ыудусе" and s5.nresults == 4 and used(s5) == "фвпр"
)
esc()

-- smartcase / ignorecase
D.lua("vim.o.ignorecase = true; vim.o.smartcase = true")
D.reset(TEXT)
D.input("ыП")
D.sync()
local s7 = snap()
D.row("4b smartcase: ы + П", "ыП", 6, s7.nresults)
esc()
D.reset(TEXT)
D.input("ып")
D.sync()
local s8 = snap()
D.row(
  "4b ignorecase: ы + п — п и П, метки есть",
  "ып",
  "37, метки",
  ("%d, меток %d"):format(s8.nresults, #s8.labeled),
  s8.nresults == 37 and #s8.labeled > 0
)
esc()
-- заглавная кириллица в продолжении при ignorecase: снимается только своя метка
D.reset({ "пР пр пф пы пж пз" })
D.input("ып")
D.sync()
local s9 = snap()
local u9 = used(s9)
D.row(
  "ignorecase: продолжения Р р ф ы — метки р ф ы сняты, остальные есть",
  "ып",
  "метки без р ф ы",
  "метки " .. u9,
  #u9 > 0 and not u9:find("р") and not u9:find("ф") and not u9:find("ы")
)
esc()
D.lua("vim.o.ignorecase = false; vim.o.smartcase = false")

-- 4d char f/t/F/T в ru (дубли keymap а/е/А/Е, ж/б)
D.reset(TEXT)
char_reset()
D.input("ар")
D.sync()
local d1 = snap("char")
D.row("4d RU: а + р (f р)", "ар", "ривет@1:2", at(d1), d1.exists and at(d1) == "ривет@1:2")
D.reset(TEXT)
char_reset()
D.input("арж")
D.sync()
D.row("4d RU: а р ж (повтор ;)", "арж", "ример@1:23", at(snap("char")))
D.reset(TEXT, { 1, 30 })
char_reset()
D.input("арб")
D.sync()
D.row("4d RU: с 1:30 а р б (повтор , назад)", "арб", "ример@1:23", at(snap("char")))
D.reset(CODE)
char_reset()
D.input("ат")
D.sync()
D.row("4d RU, код: а + т (f n, латинская n)", "ат", "nction@1:8", at(snap("char")))
D.reset(CODE)
char_reset()
D.input("ет")
D.sync()
D.row("4d RU, код: е + т (t n)", "ет", "unction@1:7", at(snap("char")))
D.reset(CODE, { 1, 12 })
char_reset()
D.input("Ат")
D.sync()
D.row("4d RU, код: с 1:12 А + т (F n)", "Ат", "nction@1:8", at(snap("char")))
D.reset(CODE, { 1, 12 })
char_reset()
D.input("Ет")
D.sync()
D.row("4d RU, код: с 1:12 Е + т (T n)", "Ет", "ction@1:9", at(snap("char")))
D.reset(TEXT)
char_reset()
D.input("вар")
D.sync()
D.row("4d RU: в а р (d f р)", "вар", "ивет, ", D.lines()[1]:sub(1, 10))

-- 4d treesitter Ы: свои метки treesitter (abcdef…), переведённые в ru
D.reset(CODE)
D.lua("vim.bo.filetype = 'lua'; vim.treesitter.start(0, 'lua'); vim.api.nvim_win_set_cursor(0, {2, 10})")
D.input("Ы")
D.sync()
-- узлы treesitter: метка, начало и конец (из состояния flash, по порядку меток)
local ts = D.lua([[
local out = {}
for _, m in ipairs(require("flash.repeat")._states.treesitter.results) do
  out[#out + 1] = { label = m.label, pos = { m.pos[1], m.pos[2] }, end_pos = { m.end_pos[1], m.end_pos[2] } }
end
return out
]])
local ts_ru = D.lua("return require('ru-layout.tr').to_ru('abcdefghijklmnopqrstuvwxyz')")
local ts_labels, node = {}, nil
for _, m in ipairs(ts) do
  ts_labels[#ts_labels + 1] = m.label
  if vim.deep_equal(m.pos, { 2, 2 }) and vim.deep_equal(m.end_pos, { 2, 30 }) then
    node = m.label
  end
end
-- метки раздаются узлам от глубокого к внешнему; сравнивается набор
table.sort(ts_labels)
local ts_want = vim.fn.split(vim.fn.strcharpart(ts_ru, 0, #ts), "\\zs")
table.sort(ts_want)
D.row(
  "4d RU: Ы — метки из набора treesitter, кириллицей",
  "Ы",
  table.concat(ts_want),
  table.concat(ts_labels),
  #ts > 0 and table.concat(ts_labels) == table.concat(ts_want)
)
D.input(node or "<Esc>")
D.sync()
D.row(
  "4d RU: Ы + метка узла local selected… (2:2)",
  "Ы" .. tostring(node),
  "v {2,3,2,31}",
  D.lua(
    "return vim.fn.mode(1) .. ' ' .. vim.inspect({vim.fn.getpos('v')[2], vim.fn.getpos('v')[3], vim.fn.getpos('.')[2], vim.fn.getpos('.')[3]})"
  ),
  D.lua("return vim.fn.mode(1)") == "v"
    and vim.deep_equal(
      D.lua("return {vim.fn.getpos('v')[2], vim.fn.getpos('v')[3], vim.fn.getpos('.')[2], vim.fn.getpos('.')[3]}"),
      { 2, 3, 2, 31 }
    )
)
esc()

-- 4d remote в ru: н к пр (y r пр) — копирование удалённого слова
D.reset(TEXT)
D.lua("require('flash.repeat')._states = {}")
D.input("нкпр")
D.sync()
local r1 = snap()
local rmode = D.lua("local s = require('flash.repeat')._states.jump; return s and s.opts.mode or 'нет'")
D.row(
  "4d RU: нкпр (y r пр)",
  "нкпр",
  "mode=remote, видим, labels=" .. LABELS_RU,
  ("mode=%s, видим=%s, labels=%s"):format(rmode, tostring(r1.visible), r1.labels or ""),
  rmode == "remote" and r1.visible == true and r1.labels == LABELS_RU
)
local rm = find_label(r1, word("правка"))
if rm then
  D.input(rm.label)
  D.sync()
  D.input("iw")
  D.sync()
end
D.row(
  "4d RU: нкпр + метка + iw — в регистре «правка», курсор на месте",
  "нкпр" .. (rm and rm.label or "?") .. "iw",
  { "правка", { 1, 0 } },
  { D.lua("return vim.fn.getreg('\"')"), D.cursor() }
)
esc()

-- treesitter_search К в x
D.reset(CODE)
D.lua("vim.bo.filetype = 'lua'; vim.treesitter.start(0, 'lua')")
D.input("vКыуд")
D.sync()
local tss = D.lua("return FS.marks()")
local tss_ok = #tss > 0
for _, m in ipairs(tss) do
  tss_ok = tss_ok and m.label:match("^[\128-\255]") ~= nil
end
D.row(
  "RU: v К ыуд (treesitter_search) — метки кириллические",
  "vКыуд",
  "метки кириллицей",
  table.concat(
    vim.tbl_map(function(m)
      return m.label
    end, tss),
    ""
  ),
  tss_ok
)
esc()

-- `/` и <c-s> (modes.search): метки по раскладке
D.reset(TEXT)
D.input("/пр<C-s>")
D.sync()
local q = D.lua([[
local st = require("flash.plugins.search").state
if not st then return { labels = "" } end
local ret = { labels = table.concat(st:labels(), "") }
for _, m in ipairs(st.results) do
  local line = vim.api.nvim_buf_get_lines(0, m.pos[1] - 1, m.pos[1], false)[1]
  if m.label and line:sub(m.pos[2] + 1):find("^правка") then
    ret.qm = { label = m.label }
  end
end
return ret
]])
local qm = q.qm
D.row(
  "RU: /пр<C-s> — метки flash в строке поиска кириллические",
  "/пр<C-s>",
  LABELS_RU,
  q.labels,
  q.labels == LABELS_RU and qm ~= nil
)
if qm then
  -- Прыжок flash из строки поиска идёт через vim.schedule, nvim_input("<esc>")
  -- и CmdlineLeave; ввод внутри vim.wait испытуемого не разбирается, поэтому ждёт
  -- драйвер: испытуемый по CursorMoved в normal сообщает о прыжке уведомлением RPC.
  _G.FLASH_JUMPED = nil
  D.lua([[
local chan
for _, c in ipairs(vim.api.nvim_list_chans()) do
  if c.stream == "stdio" then chan = c.id end
end
vim.api.nvim_create_autocmd("CursorMoved", {
  callback = function()
    if vim.fn.mode() == "n" then
      vim.rpcnotify(chan, "nvim_exec_lua", "_G.FLASH_JUMPED = true", {})
      return true
    end
  end,
})
]])
  D.input(qm.label)
  vim.wait(2 ^ 31 - 1, function()
    return _G.FLASH_JUMPED
  end, 1)
end
D.row(
  "RU: /пр<C-s> + метка → «правка»",
  "/пр<C-s>" .. (qm and qm.label or "?"),
  { 3, 59 },
  D.cursor()
)
D.lua("require('flash').toggle(false)")

-- повторный setup() ничего не меняет
D.row(
  "setup: повторный вызов не оборачивает дважды",
  "RUF.setup()",
  true,
  D.lua([[
local C = require("flash.commands")
local j, m = C.jump, require("flash.plugins.char").mode
local ok = RUF.setup()
return ok and C.jump == j and require("flash.plugins.char").mode == m
]])
)
D.stop()

-- ===================== Экземпляр 2: без Hyprland (layout.get() == nil) =====================
D.start({ langmap = true, plugins = { "flash.nvim" } })
D.lua(SETUP, false)
D.check("без Hyprland: layout.get() == nil, setup установлен", { true, true }, {
  D.lua("return require('ru-layout.layout').get() == nil"),
  D.lua("return RUF_OK"),
})
D.reset(TEXT)
D.input("ыпр")
D.sync()
local n1 = snap()
D.row(
  "без Hyprland: ы + пр — метки латинские",
  "ыпр",
  "asdfghjklqwertyuiopzxcvbnm…",
  n1.labels:sub(1, 26),
  n1.labels:sub(1, 26) == "asdfghjklqwertyuiopzxcvbnm" and n1.search == "\\V\\[пg]\\[рh]"
)
pick("без Hyprland: метка y → «проект»", n1, "проект", "y")
D.reset(TEXT)
char_reset()
D.input("ар")
D.sync()
D.row("без Hyprland: а + р (f р)", "ар", "ривет@1:2", at(snap("char")))
D.stop()

-- ===================== Экземпляр 3: изменённые внутренности flash =====================
D.start({ plugins = { "flash.nvim" } })
local guard = D.lua([[
_G.NOTES = {}
vim.notify = function(msg, level) table.insert(NOTES, { msg = msg, level = level }) end
require("flash").setup({})
local F = require("ru-layout.flash")
local Char = require("flash.plugins.char")
local mode = Char.mode
Char.mode = nil
local r1 = F.setup()
local r2 = F.setup()
Char.mode = mode
local Labeler = require("flash.labeler")
local skip = Labeler.skip
Labeler.skip = nil
local ok3, why3 = F.check()
local r3 = F.setup()
Labeler.skip = skip
return {
  r1 = r1, r2 = r2, r3 = r3, why3 = why3, ok3 = ok3,
  notes = #NOTES,
  level = NOTES[1] and NOTES[1].level,
  msg = NOTES[1] and NOTES[1].msg or "",
  wrapped = require("flash.commands")._ru_layout ~= nil,
  char_patched = Char._ru_layout ~= nil,
  check_now = F.check(),
}
]])
D.row(
  "защита: Char.mode = nil — setup не патчит, одно предупреждение WARN",
  "Char.mode = nil; setup() ×2",
  { false, false, 1, vim.log.levels.WARN, true, false, false },
  {
    guard.r1,
    guard.r2,
    guard.notes,
    guard.level,
    guard.msg:find(
      "ru-layout: внутренности flash изменились, откатите flash по lazy-lock.json",
      1,
      true
    ) == 1,
    guard.wrapped,
    guard.char_patched,
  }
)
D.row(
  "защита: Labeler.skip = nil — check() сообщает причину, setup не патчит",
  "Labeler.skip = nil",
  { false, "flash.labeler.skip", false, 1 },
  { guard.ok3, guard.why3, guard.r3, guard.notes }
)
D.check("защита: после восстановления check() проходит", true, guard.check_now)
D.stop()
D.finish()
