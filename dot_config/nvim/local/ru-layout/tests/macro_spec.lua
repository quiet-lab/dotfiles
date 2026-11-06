-- Обёртка `@` (ru-layout.macro): воспроизведение макросов, записанных в русской
-- раскладке (проверка D3 проекта), `@@`, `@:`, `:normal @a`, `:g/…/normal @a`.
-- Запуск: cd <корень плагина> && nvim -l tests/macro_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

D.start({ langmap = true, hypr = "ru", plugins = { "flash.nvim" } })
-- Раскладка из двойника: ожидание первого события до get() == "ru".
D.lua([[
local L = require("ru-layout.layout")
L.setup()
vim.wait(2 ^ 31 - 1, function() return L.get() == "ru" end, 1)
require("ru-layout.macro").setup()
require("ru-layout.macro").setup()
]])

local function at(keys, lines)
  return { lines = lines or { "abcdef" } }
end

D.check(
  "одна привязка @ после двух setup()",
  1,
  D.lua([[
local n = 0
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  if m.lhs == "@" then n = n + 1 end
end
return n]])
)

-- D3: запись в RU, воспроизведение обёрткой.
D.case("D3 запись в RU йфчй, @a", "йфчй@a", { "cdef" }, D.lines, at())
D.case("D3 2@a", "йфчй2@a", { "def" }, D.lines, at())
D.reset({ "abc" })
D.input("йфШпр<Esc>")
D.sync()
D.input("й")
D.sync()
D.input("@a")
D.sync()
D.row(
  "D3 макрос с русским текстом вставки (порциями)",
  "йфШпр<Esc>¦й¦@a",
  { "прпрabc" },
  D.lines()
)
D.case("D3 @ф (имя регистра кириллицей)", "йфчй@ф", { "cdef" }, D.lines, at())
D.case("D3 контроль: латинский qaxq@a", "qaxq@a", { "cdef" }, D.lines, at())
D.case("@@ повторяет последний макрос", "йфчй@a@@", { "def" }, D.lines, at())
D.case('@" в RU = @@ (клавиша @)', 'йфчй@a@"', { "def" }, D.lines, at())
D.case(
  "@Ж в RU = @: (повтор командной строки)",
  ":s/a/X/<CR>j@Ж",
  { "Xbc", "Xbc" },
  D.lines,
  { lines = { "abc", "abc" } }
)
D.case("@<Esc> ничего не делает", "@<Esc>", { "abcdef" }, D.lines, at())

-- :normal без ! применяет привязки: обёртка срабатывает и там.
D.case(":normal @a с макросом из RU", "йфчй:normal @a<CR>", { "cdef" }, D.lines, at())
D.case(":normal 2@a", "йфчй:normal 2@a<CR>", { "def" }, D.lines, at())
D.case(
  ":g/x/normal @a с макросом из RU",
  "йфчйu:g/x/normal @a<CR>",
  { "xy", "ab", "xy" },
  D.lines,
  { lines = { "zxy", "ab", "zxy" }, show = "йфчй u :g/x/normal @a" }
)
D.case(
  ":normal @a с русским текстом вставки",
  "йфШпр<Esc>йu:normal @a<CR>",
  { "прabc" },
  D.lines,
  { lines = { "abc" }, show = "йфШпр<Esc>й u :normal @a" }
)
D.case(":normal @a, затем остаток строки", "йфчй:normal @ax<CR>", { "def" }, D.lines, at())
D.case(
  ":normal @alx с русским текстом вставки и остатком",
  "йфaпр<Esc>йu0:normal @alx<CR>",
  { "aпрc" },
  D.lines,
  { lines = { "abc" }, show = "йфaпр<Esc>й u0 :normal @alx" }
)
D.case(
  "@alx одной порцией: <Esc> макроса не сливается с l",
  "qaaпр<Esc>qu0@alx",
  { "aпрc" },
  D.lines,
  { lines = { "abc" } }
)
D.case(
  "запись макроса с вложенным @a не дублирует его содержимое",
  "йфчйqb@aq",
  "@a",
  function()
    return D.lua("return vim.fn.getreg('b')")
  end,
  at()
)
D.check("'langremap' восстановлен", false, D.lua("return vim.o.langremap"))

-- Английская раскладка: ASCII-знаки в имени регистра не переводятся.
D.hypr_switch("us")
D.case(
  "US: @: повторяет командную строку",
  ":s/a/X/<CR>j@:",
  { "Xbc", "Xbc" },
  D.lines,
  { lines = { "abc", "abc" } }
)
D.case("US: макрос из RU воспроизводится и в US", "йфчй@a", { "cdef" }, D.lines, at())
D.case("US: латинский qaxq2@a", "qaxq2@a", { "def" }, D.lines, at())

D.stop()
D.finish()
