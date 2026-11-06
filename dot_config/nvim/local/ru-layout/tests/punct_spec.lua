-- Знаки по раскладке (ru-layout.punct): проверка D2 проекта и остальные знаки
-- `"` → `@`, `;` → `$`, `:` → `^`, `?` → `&`, `/` → `|`; прежние действия
-- в английской раскладке и на парных кириллических клавишах; порядок с flash.
-- Запуск: cd <корень плагина> && nvim -l tests/punct_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

local function cmdtype()
  return D.lua("return vim.fn.mode() .. vim.fn.getcmdtype()")
end
local function L(lines, cur)
  return { lines = lines, cur = cur }
end

-- Как в рабочей конфигурации: keymap.install() до плагинов, затем flash,
-- затем обёртка `@` и знаки.
local SETUP = [[
local code = ...
local Lay = require("ru-layout.layout")
Lay.setup()
vim.wait(2 ^ 31 - 1, function() return Lay.get() == code end, 1)
require("ru-layout.keymap").install()
]]

D.start({ langmap = true, hypr = "ru", plugins = { "flash.nvim" } })
D.lua(SETUP, "ru")
D.lua([[
require("flash").setup({})
require("ru-layout.macro").setup()
require("ru-layout.punct").setup()
require("ru-layout.punct").setup()
]])

D.check(
  "одна привязка на знак в n/x/o после двух setup()",
  { 1, 1, 1 },
  D.lua([[
local res = {}
for i, mode in ipairs({ "n", "x", "o" }) do
  res[i] = 0
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhs == "." then res[i] = res[i] + 1 end
  end
end
return res]])
)
D.check(
  "прежнее действие ; и , — обработчик flash",
  { true, true },
  D.lua([[
local P = require("ru-layout.punct")
local res = {}
for _, s in ipairs(P._slots) do
  if s.mode == "n" and (s.key == ";" or s.key == ",") then
    res[#res + 1] = s.prev ~= nil and type(s.prev.callback) == "function"
  end
end
return res]])
)
D.check(
  "пары ю б Э ж Ж — прежнее действие, не дубль знака",
  {
    "ru-layout: прежнее действие знака",
    "ru-layout: прежнее действие знака",
    "ru-layout: прежнее действие знака",
    "ru-layout: прежнее действие знака",
    "ru-layout: прежнее действие знака",
  },
  D.lua([[
local res = {}
for _, k in ipairs({ "ю", "б", "Э", "ж", "Ж" }) do
  res[#res + 1] = vim.fn.maparg(k, "n", false, true).desc
end
return res]])
)

-- Русская раскладка.
D.case("D2 RU: . (клавиша /) открывает поиск", ".", "c/", cmdtype, L({ "abc" }))
D.case("D2 RU: ю (клавиша .) = повтор", "чю", { "cdef" }, D.lines, L({ "abcdef" }))
D.case("D2 RU: 3ю — повтор со счётчиком", "ч3ю", { "ef" }, D.lines, L({ "abcdef" }))
D.case("D2 RU: , (клавиша ?) открывает обратный поиск", ",", "c?", cmdtype, L({ "abc" }))
D.case(
  'RU: " (клавиша @) воспроизводит макрос: йфчй"a',
  'йфчй"a',
  { "cdef" },
  D.lines,
  L({ "abcdef" })
)
D.case('RU: "ф — имя регистра кириллицей', 'йфчй"ф', { "cdef" }, D.lines, L({ "abcdef" }))
D.case("RU: ; (клавиша $) — конец строки", ";", { 1, 6 }, D.cursor, L({ "abc def" }))
D.case("RU: в; (d$) в ожидании оператора", "в;", { "abc " }, D.lines, L({ "abc def" }, { 1, 4 }))
D.case(
  "RU: : (клавиша ^) — первый непробельный",
  ":",
  { 1, 2 },
  D.cursor,
  L({ "  abc" }, { 1, 4 })
)
D.case("RU: ? (клавиша &) повторяет :s", "Жs/a/b/<CR>j?", { "ba", "ba" }, D.lines, L({ "aa", "aa" }))
D.case("RU: 3/ (клавиша |) — колонка 3", "3/", { 1, 2 }, D.cursor, L({ "abcdef" }))
D.case("RU: / без счётчика — колонка 1", "/", { 1, 0 }, D.cursor, L({ "abcdef" }, { 1, 4 }))
D.case("RU: Ж открывает командную строку", "Ж", "c:", cmdtype, L({ "abc" }))
D.case("RU: Э — регистр: Эфнн", "Эфнн", "abc\n", function()
  return D.lua("return vim.fn.getreg('a')")
end, L({ "abc" }))
D.case(
  "RU: Аbжб — повтор flash char ж и б",
  "Аbжб",
  { 1, 7 },
  D.cursor,
  L({ "ab ab ab ab" }, { 1, 10 })
)
D.case("RU: м; (v$) в visual", "м;в", { "" }, D.lines, L({ "abc" }))

-- Английская раскладка: прежние действия.
D.hypr_switch("us")
D.case("D2 US: . = повтор (x затем .)", "x.", { "cdef" }, D.lines, L({ "abcdef" }))
D.case("D2 US: 3. счётчик повтора", "x3.", { "ef" }, D.lines, L({ "abcdef" }))
D.case(
  "D2 US: , = обратный повтор flash char (Fb ; ,)",
  "$Fb;,",
  { 1, 7 },
  D.cursor,
  L({ "ab ab ab ab" })
)
D.case("D2 US: d. оператор + повтор", "dw.", { "c" }, D.lines, L({ "a b c" }))
D.case("US: ; = повтор flash char (fb;)", "fb;", { 1, 4 }, D.cursor, L({ "ab ab ab" }))
D.case("US: d; — оператор с повтором flash", "fbd;", { "a ab" }, D.lines, L({ "ab ab ab" }))
D.case("US: / открывает поиск", "/", "c/", cmdtype, L({ "abc" }))
D.case("US: ? открывает обратный поиск", "?", "c?", cmdtype, L({ "abc" }))
D.case("US: : открывает командную строку", ":", "c:", cmdtype, L({ "abc" }))
D.case('US: "ayy — регистр', '"ayy', "abc\n", function()
  return D.lua("return vim.fn.getreg('a')")
end, L({ "abc" }))
D.case('US: "_dd — чёрная дыра', 'yy"_dd', "abc\n", function()
  return D.lua("return vim.fn.getreg('\"')")
end, L({ "abc", "def" }))
D.case("US: /b<CR> ищет", "/b<CR>", { 1, 1 }, D.cursor, L({ "abc" }))

-- Привязка поверх модуля становится прежним действием по User LazyLoad.
D.lua([[
vim.g.semi = 0
vim.keymap.set("n", ";", function() vim.g.semi = vim.g.semi + 1 end)
vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "other" })
]])
D.case("US: ; поверх модуля — прежнее действие после LazyLoad", ";", 1, function()
  return D.lua("return vim.g.semi")
end, L({ "abc" }))
D.hypr_switch("ru")
D.case("RU: ; после LazyLoad — снова $", ";", { 1, 2 }, D.cursor, L({ "abc" }))
D.stop()

-- Порядок с lazy.nvim: flash ещё не загружен — ; и , не заняты, после
-- User LazyLoad прежним действием становится flash.
D.start({ langmap = true, hypr = "us", plugins = { "flash.nvim" } })
D.lua(SETUP, "us")
D.lua([[
package.loaded["lazy.core.config"] = { plugins = { ["flash.nvim"] = { _ = {} } } }
require("ru-layout.macro").setup()
require("ru-layout.punct").setup()
]])
D.check(
  "lazy: до загрузки flash ; и , свободны",
  { "", "" },
  D.lua("return { vim.fn.maparg(';', 'n'), vim.fn.maparg(',', 'n') }")
)
D.check(
  "lazy: . занят сразу",
  "ru-layout: знак по раскладке",
  D.lua("return vim.fn.maparg('.', 'n', false, true).desc")
)
D.lua([[
require("flash").setup({})
package.loaded["lazy.core.config"].plugins["flash.nvim"]._.loaded = {}
vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "flash.nvim" })
]])
D.check(
  "lazy: после LazyLoad ; — привязка модуля",
  "ru-layout: знак по раскладке",
  D.lua("return vim.fn.maparg(';', 'n', false, true).desc")
)
D.case("lazy US: $Fb;, — повтор flash", "$Fb;,", { 1, 7 }, D.cursor, L({ "ab ab ab ab" }))
D.hypr_switch("ru")
D.case("lazy RU: ; — конец строки", ";", { 1, 6 }, D.cursor, L({ "abc def" }))
D.stop()
D.finish()
