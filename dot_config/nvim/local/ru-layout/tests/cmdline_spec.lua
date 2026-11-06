-- Командная строка: перевод строки `:` по <CR>, перевод слова перед <Tab>
-- (встроенное дополнение и blink.cmp), шаблон по обеим раскладкам в `/` (<M-l>),
-- буфер ввода claude-input (вариант D).
-- Запуск: cd <корень плагина> && nvim -l tests/cmdline_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = here .. "/../lua/?.lua;" .. package.path
local D = dofile(here .. "/harness/drv.lua")

-- Правило перевода как функция: строка → перевод (без запуска команд).
local function rule(line, expect)
  local fact = D.lua("return require('ru-layout.cmdline').translate(...)", line)
  D.row("правило", line, expect, fact)
end

-- Последняя выполненная команда и ошибка.
local function last()
  return D.lua("return { vim.fn.histget(':', -1), vim.v.errmsg }")
end

-- Порядок как в рабочей конфигурации: подмена API привязок до модулей.
local SETUP = [[
vim.v.errmsg = ''
require('ru-layout.keymap').install()
require('ru-layout.cmdline').setup()
]]

D.start({ langmap = true })
D.lua(SETUP)

-- Таблица правила.
rule("ц", "w")
rule("цй", "wq")
rule("йф!", "qa!")
rule("в", "d")
rule("ыуе тгьиук", "set number")
rule("ыуе тщтгьиук", "set nonumber")
rule("ыуе еы=4", "set ts=4")
rule("ыуе ае=дгф", "set ft=lua")
rule("ыуе ешедуыекштп=Привет", "set titlestring=Привет")
rule("у файл.txt", "e файл.txt")
rule("%ы/старое/новое/п", "%s/старое/новое/g")
rule("ы.старое.новое.пс", "s.старое.новое.gc")
rule("п/x/тщкьфд @a", "g/x/normal @a")
rule("п!/x/в", "g!/x/d")
rule("'<,'>ы/a/b/", "'<,'>s/a/b/")
rule("э<,э>в", "'<,'>d")
rule("ю,;в", ".,;d")
rule('усрщ "привет"', 'echo "привет"')
rule("дуе g:z='привет'", "let g:z='привет'")
rule("let g:z='привет'", "let g:z='привет'")
rule("s/а/б/п", "s/а/б/п")
rule("sу", "sу")
rule("рудз ьфз", "help map")
rule("сщдщкысруьу", "colorscheme")
rule("ышдуте! ц", "silent! w")
rule("vert рудз ьфз", "vert help map")
rule("тщкь фй", "norm фй")
rule("ттщкуьфз ф в", "nnoremap a в")
rule("шьфз ф в", "imap ф в")
rule("фгещсьв ИгаЦкшеуЗку *.lua echo 'привет'", "autocmd BufWritePre *.lua echo 'привет'")
rule("ЮЮ", ">>")
rule("ыпс", "sgc")
rule("!ls фыв", "!ls фыв")
rule("привет мир", "ghbdtn мир")

-- Пользовательские команды: с дополнением-ключевыми словами и с файлом.
D.lua([[
vim.api.nvim_create_user_command('Zkw', function(o) _G.ZKW = o.args end,
  { nargs = '*', complete = function() return { 'update', 'sync' } end })
vim.api.nvim_create_user_command('Zfile', function(o) _G.ZF = o.args end, { nargs = 1, complete = 'file' })
]])
rule("Zkw гзвфеу", "Zkw гзвфеу")
rule("Zkw привет", "Zkw привет")
rule("Zfile гзвфеу", "Zfile гзвфеу")
rule("Яашду гзвфеу", "Zfile гзвфеу")
rule("Ялц гзвфеу", "Zkw update")

-- D4 и сквозные случаи: <CR> выполняет переведённую строку.
D.lua([[
_G.W = 0
vim.api.nvim_create_autocmd('BufWriteCmd', { pattern = 'acw://*', callback = function() _G.W = _G.W + 1; vim.bo.modified = false end })
]])
local ACW = "vim.cmd('file acw://t'); vim.bo.buftype='acwrite'; vim.bo.modified=true"
D.case("D4: Жц<CR> в буфере acwrite", "Жц<CR>", 1, function()
  return D.lua("local w=_G.W; _G.W=0; return w")
end, { lines = { "x" }, pre = ACW })
D.case(":let с кириллицей не тронут", ":let g:z='привет'<CR>", "привет", function()
  return D.lua("return vim.g.z")
end)
D.case("D4: Жв<CR> = :d", "Жв<CR>", { "b" }, D.lines, { lines = { "a", "b" } })
local ok = D.lua("return {pcall(vim.cmd, 'command Пр echo 1')}")
D.row(
  "D4: кириллическое имя команды",
  "command Пр",
  "недопустимо",
  ok[1] and "принята" or "недопустимо"
)
D.case("Жцй<CR> = :wq (запись и закрытие окна)", "Жцй<CR>", { 1, 1 }, function()
  return D.lua("local w=_G.W; _G.W=0; return { w, vim.fn.winnr('$') }")
end, { lines = { "x" }, pre = "vim.cmd('new'); " .. ACW })
D.case("Жыуе тгьиук<CR>", "Жыуе тгьиук<CR>", { true, { "set number", "" } }, function()
  return { D.lua("return vim.o.number"), last() }
end)
D.case("Жыуе тщтгьиук<CR>", "Жыуе тщтгьиук<CR>", false, function()
  return D.lua("return vim.o.number")
end)
D.case(
  "Жу файл.txt<CR>: кириллический путь сохранён",
  "Жу файл.txt<CR>",
  "файл.txt",
  function()
    return D.lua("return vim.fn.expand('%:t')")
  end
)
D.case(
  "Ж%ы/старое/новое/п<CR>",
  "Ж%ы/старое/новое/п<CR>",
  { "новое и новое", "x новое" },
  D.lines,
  { lines = { "старое и старое", "x старое" } }
)
D.case(
  "Жп/x/тщкьфд @a<CR> с макросом qaxq",
  "qaxqЖп/x/тщкьфд @a<CR>",
  { "z", "1", "y2", "3" },
  D.lines,
  {
    lines = { "zz", "x1", "y2", "x3" },
  }
)
D.case("VjЖы/a/b/<CR>: диапазон '<,'>", "VjЖы/a/b/<CR>", { "b a", "b a", "a" }, D.lines, {
  lines = { "a a", "a a", "a" },
})
D.case('Жусрщ "привет"<CR>', 'Жусрщ "привет"<CR>', { 'echo "привет"', "" }, last)
D.case("Ждуе g:z='привет'<CR>", "Ждуе g:y='привет'<CR>", "привет", function()
  return D.lua("return vim.g.y")
end)
D.case(
  "Жрудз ьфз<CR>: справка по map",
  "Жрудз ьфз<CR>",
  { "help", { "help map", "" } },
  function()
    local r = { D.lua("return vim.bo.buftype"), last() }
    D.lua("vim.cmd('helpclose')")
    return r
  end
)
D.case("Жсщдщкысруьу<CR>", "Жсщдщкысруьу<CR>", { "colorscheme", "" }, last)
D.case(
  "ЖЯлц гзвфеу<CR>: пользовательская команда",
  "ЖЯлц гзвфеу<CR>",
  "update",
  function()
    return D.lua("return _G.ZKW")
  end
)

-- <Tab> без blink: встроенное дополнение по переведённому слову.
local function cmdline()
  return D.lua("return vim.fn.getcmdline()")
end
D.case("<Tab> без blink: Жув<Tab> → edit", "Жув<Tab>", "edit", cmdline)
D.case("<Tab> без blink: Жыуе тг<Tab> → set nu…", "Жыуе тг<Tab>", "set nu…", function()
  local l = cmdline()
  return vim.startswith(l, "set nu") and #l > 6 and "set nu…" or l
end)
D.case("<Tab> без blink: путь не переводится", "Жу фа<Tab>", "e фа", cmdline)

-- <M-l> в `/`: шаблон по обеим раскладкам и обратно.
local TEXT = { "abc sel x", "sel y" }
D.case("<M-l>: /ыуд → шаблон", "/ыуд<M-l>", "\\V\\[ыs]\\[уe]\\[дl]", cmdline, { lines = TEXT })
D.case("<M-l>: поиск находит sel", "/ыуд<M-l><CR>", { 1, 4 }, D.cursor, { lines = TEXT })
D.case("<M-l>: n идёт дальше", "/ыуд<M-l><CR>n", { 2, 0 }, D.cursor, { lines = TEXT })
D.case(
  "<M-l>: повторное нажатие возвращает ыуд",
  "/ыуд<M-l><M-l>",
  "ыуд",
  cmdline,
  { lines = TEXT }
)
D.case(
  "<M-l>: русский текст тоже находится",
  "/sel<M-l><CR>",
  { 1, 4 },
  D.cursor,
  { lines = { "abc ыуд x" } }
)
-- Встроенный incsearch при `/sel` ставит курсор в конец совпадения ({ 1, 7 }).
D.case("<M-l>: incsearch как у /sel", "/ыуд<M-l>", { 1, 7 }, function()
  return D.lua("return vim.api.nvim_win_get_cursor(0)")
end, { lines = TEXT })
D.case(
  "<M-д> (дубль keymap): /ыуд → шаблон",
  "/ыуд<M-д>",
  "\\V\\[ыs]\\[уe]\\[дl]",
  cmdline,
  { lines = TEXT }
)
D.check(
  "<M-д> — дубль модуля keymap, удаляется вместе с <M-l>",
  { true, "" },
  D.lua([[
local had = vim.fn.maparg('<M-д>', 'c') ~= ''
vim.keymap.del('c', '<M-l>')
local after = vim.fn.maparg('<M-д>', 'c')
require('ru-layout.cmdline').setup()
return { had, after }
]])
)
D.case("<M-l>: в `:` вставка без перевода", ":ab<M-l><C-u>echo 1<CR>", "", function()
  return D.lua("return vim.v.errmsg")
end)

-- Вариант D: настоящий модуль claude-input, набор в RU, :w через Жц.
D.lua(
  [[
local dir = ...
vim.opt.rtp:prepend(dir)
local ci = require('claude_input')
ci.setup()
_G.HIT = {}
ci.submit = function() table.insert(_G.HIT, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')) end
]],
  D.root .. "/../claude-input"
)
local function hit()
  return D.lua(
    "local h = _G.HIT; _G.HIT = {}; return { vim.api.nvim_buf_get_name(0):match('claude://input') and 'claude://input' or vim.api.nvim_buf_get_name(0), h }"
  )
end
D.case(
  "вариант D: iпривет<Esc>Жц<CR>",
  "iпривет<Esc>Жц<CR>",
  { "claude://input", { "привет" } },
  hit,
  {
    pre = "vim.cmd('ClaudeInput'); vim.cmd('stopinsert'); vim.api.nvim_buf_set_lines(0,0,-1,false,{})",
  }
)
D.case(
  "вариант D: :w латиницей",
  "iтекст<Esc>:w<CR>",
  { "claude://input", { "текст" } },
  hit,
  {
    pre = "vim.cmd('ClaudeInput'); vim.cmd('stopinsert'); vim.api.nvim_buf_set_lines(0,0,-1,false,{})",
  }
)
D.stop()

-- <Tab> с blink.cmp: привязки blink ставятся асинхронно после загрузки, модуль
-- переставляет свою поверх них и вызывает прежнее действие blink.
D.start({ langmap = true, plugins = { "blink.cmp" } })
D.lua(SETUP)
D.lua([[
require('blink.cmp').setup({
  fuzzy = { implementation = 'lua' },
  sources = { default = {} },
  cmdline = { enabled = true, keymap = { preset = 'cmdline' }, completion = { menu = { auto_show = true } } },
})
vim.api.nvim_exec_autocmds('User', { pattern = 'LazyLoad', data = 'blink.cmp' })
-- Ожидание события: blink поставил привязки, модуль — свою поверх.
vim.wait(2 ^ 31 - 1, function()
  local m = vim.fn.maparg('<S-Tab>', 'c', false, true)
  return m.desc ~= nil and vim.startswith(m.desc, 'blink.cmp')
end, 1)
]])
D.check(
  "blink: <Tab> модуля поверх blink",
  { "ru-layout: перевод слова перед дополнением", true },
  D.lua([[
local m = vim.fn.maparg('<Tab>', 'c', false, true)
local p = require('ru-layout.cmdline')._prev('<Tab>')
return { m.desc, p ~= nil and vim.startswith(p.desc or '', 'blink.cmp') }
]])
)
D.check(
  "blink: <CR> в пресете cmdline не привязан",
  { "ru-layout: перевод строки : по раскладке" },
  D.lua("return { vim.fn.maparg('<CR>', 'c', false, true).desc }")
)
-- Меню blink заполняется асинхронно: ожидание до видимого меню (событие продукта).
local function blink_state()
  return D.lua([[
local cmp = require('blink.cmp')
vim.wait(2 ^ 31 - 1, function() return cmp.is_menu_visible() end, 1)
local items = {}
for _, it in ipairs(require('blink.cmp.completion.list').items or {}) do items[#items + 1] = it.label end
return { line = vim.fn.getcmdline(), has = items }
]])
end
D.case("blink: Жув<Tab> → меню команд по ed", "Жув<Tab>", "edit", function()
  local st = blink_state()
  return vim.tbl_contains(st.has, "edit") and vim.startswith(st.line, "e") and "edit" or st
end)
D.case("blink: Жыуе тг<Tab> → меню опций nu…", "Жыуе тг<Tab>", "number", function()
  local st = blink_state()
  return vim.tbl_contains(st.has, "number") and vim.startswith(st.line, "set n") and "number" or st
end)
D.case(
  "blink: <CR> после <Tab> выполняет команду",
  "Жыуе тгьиук<Tab><C-e><CR>",
  true,
  function()
    return D.lua("return vim.o.number")
  end
)
D.stop()

-- <Tab> blink с "fallback": blink запоминает прежнюю привязку (первую привязку
-- модуля) как свой запасной вариант; модуль переставляет свою поверх blink.
-- Цепочка «модуль → blink → fallback (прежняя привязка модуля)» должна закончиться
-- встроенным дополнением, а не возвращаться в blink без конца.
D.start({ langmap = true, plugins = { "blink.cmp" } })
D.lua(SETUP)
D.lua([[
_G.TABS = 0
require('blink.cmp').setup({
  fuzzy = { implementation = 'lua' },
  sources = { default = {} },
  cmdline = {
    enabled = true,
    keymap = {
      preset = 'cmdline',
      ['<Tab>'] = { function() _G.TABS = _G.TABS + 1; return false end, 'fallback' },
    },
    completion = { menu = { auto_show = false } },
  },
})
vim.api.nvim_exec_autocmds('User', { pattern = 'LazyLoad', data = 'blink.cmp' })
vim.wait(2 ^ 31 - 1, function()
  local m = vim.fn.maparg('<S-Tab>', 'c', false, true)
  return m.desc ~= nil and vim.startswith(m.desc, 'blink.cmp')
end, 1)
]])
D.case(
  "blink fallback: Жув<Tab> → встроенное дополнение edit",
  "Жув<Tab>",
  { "edit", 1, "" },
  function()
    return D.lua("return { vim.fn.getcmdline(), _G.TABS, vim.v.errmsg }")
  end,
  { pre = "_G.TABS = 0; vim.v.errmsg = ''" }
)
D.stop()
D.finish()
