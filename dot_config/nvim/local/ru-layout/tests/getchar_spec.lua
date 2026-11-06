-- Перевод getchar/getcharstr на время вызова: ru-layout.getchar.
-- Запуск: cd <корень плагина> && nvim -l tests/getchar_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

D.start({})
D.lua([[
_G.G = require("ru-layout.getchar")
_G.H = {}
_G.orig = { gc = vim.fn.getchar, gs = vim.fn.getcharstr }
local function rec(v) _G.H[#_G.H + 1] = v end
vim.keymap.set("n", "<F2>", function() rec(G.with_tr(function() return vim.fn.getcharstr() end)) end)
vim.keymap.set("n", "<F3>", function() rec(vim.fn.getcharstr()) end)
vim.keymap.set("n", "<F4>", function() rec(G.with_tr(function() return vim.fn.getchar() end)) end)
vim.keymap.set("n", "<F5>", function()
  local ok, err = pcall(G.with_tr, function()
    rec(vim.fn.getcharstr())
    error("сбой внутри", 0)
  end)
  rec(ok)
  rec(err)
  rec(vim.fn.getcharstr == _G.orig.gs and vim.fn.getchar == _G.orig.gc)
end)
vim.keymap.set("n", "<F6>", function()
  G.with_tr(function()
    rec(vim.fn.getcharstr())
    G.with_tr(function() rec(vim.fn.getcharstr()) end)
    rec(vim.fn.getcharstr())
  end)
  rec(vim.fn.getcharstr == _G.orig.gs and vim.fn.getchar == _G.orig.gc)
end)
_G.T = { read = function() return vim.fn.getcharstr() end }
vim.keymap.set("n", "<F7>", function() rec(_G.T.read()) end)
]])

local function H()
  return D.lua("local h = _G.H; _G.H = {}; return h")
end
local function run(name, keys, expect)
  D.reset({ "abc" })
  D.input(keys)
  local st = D.sync()
  D.row(name, keys, expect, st:match("^BLOCKING") and st or H())
end

run("getcharstr: ы → s", "<F2>ы", { "s" })
run("getcharstr: Ы → S", "<F2>Ы", { "S" })
run("getcharstr: латиница не тронута", "<F2>a", { "a" })
run("getcharstr: <Esc> не тронут", "<F2><Esc>", { "\27" })
run("getcharstr: знак ю → .", "<F2>ю", { "." })
run("getchar: ы → 115", "<F4>ы", { 115 })
run("getchar: латиница 97", "<F4>a", { 97 })
run("getchar: <Esc> 27", "<F4><Esc>", { 27 })
run("getchar: <Left> строкой как есть", "<F4><Left>", { vim.keycode("<Left>") })
run("getchar: цифра", "<F4>1", { 49 })
run(
  "ошибка внутри: пробрасывается, функции восстановлены",
  "<F5>ы",
  { "s", false, "сбой внутри", true }
)
run(
  "вложенные вызовы: перевод и восстановление",
  "<F6>ыва",
  { "s", "d", "f", true }
)
run("вне with_tr перевода нет", "<F3>ы", { "ы" })

-- wrap и wrap_fn
D.lua([[
G.wrap(_G.T, "read")
_G.first = _G.T.read
G.wrap(_G.T, "read")
]])
run("wrap: функция таблицы переводит", "<F7>ы", { "s" })
D.check(
  "wrap: повторный вызов не оборачивает дважды",
  true,
  D.lua("return _G.T.read == _G.first")
)
D.check("wrap: нет функции — false", false, D.lua("return G.wrap({}, 'nope')"))
D.check(
  "wrap_fn: все значения, включая nil в середине",
  { 3, 1, true, 3 },
  D.lua(
    "local r = vim.F.pack_len(G.wrap_fn(function() return 1, nil, 3 end)()); return { r.n, r[1], r[2] == nil, r[3] }"
  )
)
D.check(
  "is_wrapped: обёртка и исходная функция",
  { true, true },
  D.lua([[
local f = function() end
local w = G.wrap_fn(f)
local ok, o = G.is_wrapped(w)
return { ok, o == f and G.wrap_fn(w) == w }
]])
)
D.check(
  "после всех случаев vim.fn не подменён",
  true,
  D.lua("return vim.fn.getcharstr == _G.orig.gs and vim.fn.getchar == _G.orig.gc")
)

D.stop()
D.finish()
