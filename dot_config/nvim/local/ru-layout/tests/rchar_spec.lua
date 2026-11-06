-- Обёртка `r` (ru-layout.rchar): аргумент замены по раскладке.
-- Запуск: cd <корень плагина> && nvim -l tests/rchar_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

D.start({ langmap = true, hypr = "ru", plugins = { "flash.nvim" } })
D.lua([[
local L = require("ru-layout.layout")
L.setup()
vim.wait(2 ^ 31 - 1, function() return L.get() == "ru" end, 1)
require("flash").setup({})
require("ru-layout.rchar").setup()
require("ru-layout.rchar").setup()
]])

D.check(
  "одна привязка r и к в n и x после двух setup()",
  { 1, 1, 1, 1 },
  D.lua([[
local res = {}
for _, mode in ipairs({ "n", "x" }) do
  for _, lhs in ipairs({ "r", "к" }) do
    local n = 0
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      if m.lhs == lhs then n = n + 1 end
    end
    res[#res + 1] = n
  end
end
return res]])
)
D.check("gr не тронут", "", D.lua("return vim.fn.maparg('gr', 'n')"))

local function L(lines)
  return { lines = lines }
end

-- Русская раскладка.
D.case("RU: rа над abc → fbc (а на клавише f)", "rа", { "fbc" }, D.lines, L({ "abc" }))
D.case("RU: rА над abc → Fbc", "rА", { "Fbc" }, D.lines, L({ "abc" }))
D.case("RU: rф над xbc → abc (ф на клавише a)", "rф", { "abc" }, D.lines, L({ "xbc" }))
D.case("RU: rф над абв → фбв", "rф", { "фбв" }, D.lines, L({ "абв" }))
D.case("RU: rф над 1 → ф", "rф", { "ф" }, D.lines, L({ "1" }))
D.case("RU: rф над ( → ф", "rф", { "ф" }, D.lines, L({ "(" }))
D.case("RU: 3rх над abcd → [[[d", "3rх", { "[[[d" }, D.lines, L({ "abcd" }))
D.case("RU: r<Esc> ничего не меняет", "r<Esc>", { "abc" }, D.lines, L({ "abc" }))
D.case("RU: r1 над abc → 1bc", "r1", { "1bc" }, D.lines, L({ "abc" }))
D.case("RU: r<CR> разбивает строку", "lr<CR>", { "a", "c" }, D.lines, L({ "abc" }))
D.case("RU: r<C-v>ф над abc — буквально", "r<C-v>ф", { "фbc" }, D.lines, L({ "abc" }))
D.case("RU: vllrа над abc → fff", "vllrа", { "fff" }, D.lines, L({ "abc" }))
D.case("RU: vllrф над абв → ффф", "vllrф", { "ффф" }, D.lines, L({ "абв" }))
D.case("RU: rа затем ю (повтор) → ffc", "rаlю", { "ffc" }, D.lines, L({ "abc" }))
D.case("RU: к (клавиша r) работает как r", "ка", { "fbc" }, D.lines, L({ "abc" }))

-- Английская раскладка.
D.hypr_switch("us")
D.case("US: rф над abc → фbc", "rф", { "фbc" }, D.lines, L({ "abc" }))
D.case("US: rx над abc → xbc", "rx", { "xbc" }, D.lines, L({ "abc" }))
D.case("US: 2rz над abc → zzc", "2rz", { "zzc" }, D.lines, L({ "abc" }))
D.case("US: vlrq над abc → qqc", "vlrq", { "qqc" }, D.lines, L({ "abc" }))

D.stop()
D.finish()
