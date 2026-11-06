-- Проверки ru-layout.keymap на оснастке: дубли привязок кириллицей по правилу
-- режимов, удаление, проход по существующим и буферным привязкам Vim script
-- (vim-fugitive, vim-dadbod-ui), совместимость с mini.pairs, yanky, which-key,
-- flash и замер стоимости подмены.
-- Запуск: cd dot_config/nvim/local/ru-layout && nvim -l tests/keymap_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = here .. "/harness/?.lua;" .. package.path
local D = require("drv")

local tmp = vim.fn.tempname()

-- Временный git-репозиторий с изменённым файлом для :Git.
local repo = tmp .. "/repo"
vim.fn.mkdir(repo, "p")
local function git(...)
  local r = vim.system({ "git", "-C", repo, ... }, { text = true }):wait()
  assert(r.code == 0, r.stderr)
end
git("init", "-q")
vim.fn.writefile({ "a" }, repo .. "/a.txt")
git("add", "a.txt")
git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init")
vim.fn.writefile({ "a", "b" }, repo .. "/a.txt")

D.start({
  langmap = true,
  plugins = {
    "flash.nvim",
    "mini.pairs",
    "which-key.nvim",
    "yanky.nvim",
    "vim-fugitive",
    "vim-dadbod",
    "vim-dadbod-ui",
  },
})

-- Счётчики вызовов в испытуемом; привязка до install() — для проверки sweep().
D.lua([[
  _G.H = {}
  _G.hit = function(name)
    return function() H[name] = (H[name] or 0) + 1 end
  end
  vim.keymap.set("n", "<leader>xb", hit("xb"), { desc = "before install" })
  require("ru-layout.keymap").install()
  require("ru-layout.keymap").install()
]])

local function H(name)
  return D.lua("return H[...] or 0", name)
end
local function maparg(lhs, mode, buf)
  return D.lua(
    [[local lhs, mode, buf = ...
    if buf then return vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode) end) end
    return vim.fn.maparg(lhs, mode)]],
    lhs,
    mode,
    buf
  )
end
local function has(lhs, mode)
  return maparg(lhs, mode) ~= ""
end

-- 1. <leader>ff → <Space>аа; описание без приписок.
D.lua([[vim.keymap.set("n", "<leader>ff", hit("ff"), { desc = "Find files" })]])
D.case("n <leader>ff", "<Space>аа", 1, function()
  return H("ff")
end)
D.check(
  "desc дубля = исходному",
  "Find files",
  D.lua([[return vim.fn.maparg("<Space>аа", "n", false, true).desc]])
)
D.check(
  "install() дважды: один дубль",
  1,
  D.lua([[return #vim.tbl_filter(function(m)
  return m.lhsraw == " аа" end, vim.api.nvim_get_keymap("n"))]])
)

-- 2. s в n, x, o → ы; встроенная s не срабатывает.
D.lua([[vim.keymap.set({ "n", "x", "o" }, "s", hit("s"), { desc = "Flash" })]])
D.case("n s → ы, текст не тронут", "ы", { 1, { "abc" } }, function()
  return { H("s"), D.lines() }
end, { lines = { "abc" } })
D.case("x s → ы", "vы", 2, function()
  return H("s")
end, { lines = { "abc" } })
D.check("o s → дубль ы", true, has("ы", "o"))
D.check("s s → дубля нет (s не задан)", false, has("ы", "s"))

-- 3. v gc → пс только в x; select вставляет текст.
D.lua([[vim.keymap.set("v", "gc", hit("gc"))]])
D.case("x gc → пс", "vпс", 1, function()
  return H("gc")
end, { lines = { "abc def" } })
D.check("s gc → дубля пс нет", false, has("пс", "s"))
D.case(
  "select: пс заменяет выделение",
  "ghпс<Esc>",
  { "псbc def" },
  D.lines,
  { lines = { "abc def" } }
)

-- 4. Буферная привязка.
D.case("буферная gl → пд", "пд", 1, function()
  return H("gl")
end, { pre = [[vim.keymap.set("n", "gl", hit("gl"), { buffer = 0 })]] })

-- 5. i <M-d> → <M-в>, ввод продолжается.
D.lua([[vim.keymap.set("i", "<M-d>", hit("md"))]])
D.check("i <M-d> → дубль <M-в>", true, has("<M-в>", "i"))
D.case("i <M-в>текст", "i<M-в>текст<Esc>", { 1, { "текст" } }, function()
  return { H("md"), D.lines() }
end)
D.lua([[vim.keymap.set("c", "<C-x>", hit("cx"))]])
D.check("c <C-x> → дубль <C-ч>", true, has("<C-ч>", "c"))

-- 6. Буквенные и знаковые привязки i (точки разрыва отмены LazyVim) не переводятся.
D.lua([[
  vim.keymap.set("i", ",", ",<c-g>u")
  vim.keymap.set("i", ".", ".<c-g>u")
  vim.keymap.set("i", ";", ";<c-g>u")
  vim.keymap.set("i", "jk", "<Esc>")
]])
D.check("i , → дубля б нет", false, has("б", "i"))
D.check("i jk → дубля ол нет", false, has("ол", "i"))
D.lua([[require("mini.pairs").setup()]])
D.case(
  "i: знаки ЙЦУКЕН как набраны",
  "iх ъ ж э б ю Э .<Esc>",
  { "х ъ ж э б ю Э ." },
  D.lines
)
D.case("mini.pairs: привет(", "iпривет(<Esc>", { "привет()" }, D.lines)
D.check(
  "i, c: кириллических привязок без модификатора нет",
  {},
  D.lua([[local r = {}
  for _, m in ipairs({ "i", "c" }) do
    for _, e in ipairs(vim.api.nvim_get_keymap(m)) do
      if e.lhs:find("[\128-\255]") and not e.lhs:find("^<") then r[#r + 1] = m .. " " .. e.lhs end
    end
  end
  return r]])
)

-- 7. c <CR> без дубля.
D.check(
  "c <CR> без дубля",
  0,
  D.lua([[local before = #vim.api.nvim_get_keymap("c")
  vim.keymap.set("c", "<CR>", hit("cr"))
  local n = #vim.api.nvim_get_keymap("c") - before
  vim.keymap.del("c", "<CR>")
  return n - 1]])
)

-- 8. Удаление удаляет дубль.
D.lua([[vim.keymap.del("n", "<leader>ff")]])
D.check("del <leader>ff → нет <Space>аа", { false, false }, { has("<Space>ff", "n"), has("<Space>аа", "n") })
D.lua([[vim.keymap.set("", "<leader>q", hit("q")); vim.keymap.del("n", "<leader>q")]])
D.check(
  'del n у привязки "": дубль n снят, x и o остались',
  { false, true, true },
  { has("<Space>й", "n"), has("<Space>й", "x"), has("<Space>й", "o") }
)

-- 9. yanky: p → з вставляет через yanky.put.
D.lua([[
  require("yanky").setup({})
  local y = require("yanky")
  local put = y.put
  y.put = function(...) H.yanky = (H.yanky or 0) + 1; return put(...) end
  vim.keymap.set({ "n", "x" }, "p", "<Plug>(YankyPutAfter)")
]])
D.case("yanky p → з", "yyз", { 1, { "abc", "abc" } }, function()
  return { H("yanky"), D.lines() }
end, { lines = { "abc" } })
D.check(
  "<Plug>-привязки не дублируются",
  {},
  D.lua([[local r = {}
  for _, m in ipairs({ "n", "x", "o", "i" }) do
    for _, e in ipairs(vim.api.nvim_get_keymap(m)) do
      if e.lhs:sub(1, 6) == "<Plug>" and e.lhs:find("[\128-\255]") then r[#r + 1] = e.lhs end
    end
  end
  return r]])
)

-- 10. sweep(): привязка, поставленная до install().
D.check("до sweep() дубля <Space>чи нет", false, has("<Space>чи", "n"))
D.lua([[require("ru-layout.keymap").sweep()]])
D.case("sweep(): <Space>чи", "<Space>чи", 1, function()
  return H("xb")
end)
D.check(
  "sweep() дважды не меняет привязки",
  0,
  D.lua([[local function n()
    local c = 0
    for _, m in ipairs({ "n", "x", "s", "o", "i", "c", "t" }) do c = c + #vim.api.nvim_get_keymap(m) end
    return c
  end
  local a = n(); require("ru-layout.keymap").sweep(); return n() - a]])
)

-- 11. Пользовательская кириллическая привязка не перекрывается дублем
-- (так plugins.lua переопределяет дубли ш/ф mini.ai). Берётся q/й: у i/ш есть
-- продолжение — встроенная `in` и её дубль `шт`, и ввод ждал бы следующую клавишу.
D.lua([[
  vim.keymap.set("o", "q", "w")
  vim.keymap.set("o", "й", "l")
  vim.keymap.set("o", "q", "e")
]])
D.case(
  "o: своя й после дубля остаётся своей",
  "dй",
  { "bc def" },
  D.lines,
  { lines = { "abc def" } }
)
D.lua([[vim.keymap.del("o", "q")]])
D.check("o: del q не снимает свою й", true, has("й", "o"))
D.check("o: sweep() перевёл встроенную in → шт", true, has("шт", "o"))
D.lua([[vim.keymap.set("n", "Д", hit("userD")); vim.keymap.set("n", "L", hit("L"))]])
D.case("n: своя Д не перекрыта дублем L", "Д", { 1, 0 }, function()
  return { H("userD"), H("L") }
end)

-- 12. which-key: дубли видны в списке привязок; пп = gg при which-key.
D.lua([[
  require("which-key").setup({})
  vim.keymap.set("n", "<leader>gg", hit("gg"), { desc = "Lazygit" })
]])
D.check(
  "which-key: <Space>пп в nvim_get_keymap(n)",
  true,
  D.lua([[for _, e in ipairs(vim.api.nvim_get_keymap("n")) do
    if e.lhsraw == " пп" then return true end
  end
  return false]])
)
D.case("which-key: <Space>пп вызывает", "<Space>пп", 1, function()
  return H("gg")
end)
D.case("which-key: пп = gg", "пп", { 1, 0 }, D.cursor, { lines = { "a", "b", "c" }, cur = { 3, 0 } })

-- 13. vim-fugitive: буферные привязки статуса (:nnoremap <buffer>).
D.reset()
D.lua("vim.cmd.cd(...); vim.cmd('Git')", repo)
local fbuf = D.lua("return vim.api.nvim_get_current_buf()")
D.check("fugitive: буфер статуса", "fugitive", D.lua("return vim.bo.filetype"))
D.check("fugitive: s → ы", maparg("s", "n", fbuf), maparg("ы", "n", fbuf))
D.check("fugitive: cc → сс", maparg("cc", "n", fbuf), maparg("сс", "n", fbuf))
D.check("fugitive: дубль непустой", true, maparg("ы", "n", fbuf) ~= "")
D.lua("vim.cmd('silent! %bwipe!')")

-- 14. vim-dadbod-ui: привязки ставятся после FileType (ftplugin и код плагина).
D.lua(
  [[vim.g.dbs = { t = "sqlite:" .. ... }
  vim.g.db_ui_use_nerd_fonts = 0
  vim.cmd("DBUI")]],
  tmp .. "/x.db"
)
local dbuf = D.lua("return vim.api.nvim_get_current_buf()")
D.check("dbui: буфер", "dbui", D.lua("return vim.bo.filetype"))
D.check("dbui: o → щ", maparg("o", "n", dbuf), maparg("щ", "n", dbuf))
D.check("dbui: дубль непустой", true, maparg("щ", "n", dbuf) ~= "")
D.lua("vim.cmd('silent! %bwipe!')")

-- 14а. Смена maplocalleader: дубль привязки, поставленной при прежнем значении,
-- удаляется вместе с ней (память переводов учитывает и maplocalleader).
D.check(
  "maplocalleader: дубли при обоих значениях удаляются со своими привязками",
  { true, true, "", "", "" },
  D.lua([[
  vim.g.maplocalleader = "\\"
  vim.keymap.set("n", "<localleader>x", hit("llx1"))
  vim.g.maplocalleader = ","
  vim.keymap.set("n", "<localleader>x", hit("llx2"))
  local r = { vim.fn.maparg("\\ч", "n") ~= "", vim.fn.maparg(",ч", "n") ~= "" }
  vim.keymap.del("n", "\\x")
  r[3] = vim.fn.maparg("\\ч", "n")
  vim.keymap.del("n", "<localleader>x")
  r[4] = vim.fn.maparg(",ч", "n")
  r[5] = vim.fn.maparg(",x", "n")
  vim.g.maplocalleader = nil
  return r]])
)

-- 14б. BufWinEnter: проход по буферным привязкам только у типов файлов из списка.
D.check(
  "BufWinEnter: обычный буфер не проходится, буфер типа dbui — проходится",
  { "", true },
  D.lua([[
  -- Буфер с привязкой Vim script (мимо подмены), тип файла — без события FileType:
  -- дубль может поставить только BufWinEnter.
  local function shown(ft)
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_call(b, function()
      vim.cmd("nnoremap <buffer> zq :echo 1<CR>")
      if ft then
        vim.cmd("noautocmd setlocal filetype=" .. ft)
      end
    end)
    vim.api.nvim_win_set_buf(0, b)
    return vim.fn.maparg("яй", "n")
  end
  local r = { shown(nil), shown("dbui") ~= "" }
  vim.cmd("silent! %bwipe!")
  return r]])
)

-- 15. Замер: 400 привязок без подмены и с подменой, sweep() по ним.
local t = D.lua([[
  local km = require("ru-layout.keymap")
  local L = "abcdefghijklmnopqrstuvwxyz"
  local function lhs(p, i)
    local a, b = math.floor(i / 26) + 1, i % 26 + 1
    return "<leader>" .. p .. L:sub(a, a) .. L:sub(b, b)
  end
  local fn = function() end
  local function ms(t0) return (vim.uv.hrtime() - t0) / 1e6 end
  local r = {}
  km.uninstall()
  local t0 = vim.uv.hrtime()
  for i = 0, 399 do vim.keymap.set("n", lhs("u", i), fn, { desc = "x" }) end
  r.base = ms(t0)
  t0 = vim.uv.hrtime()
  km.install()
  r.install = ms(t0)
  t0 = vim.uv.hrtime()
  for i = 0, 399 do vim.keymap.set("n", lhs("m", i), fn, { desc = "x" }) end
  r.hooked = ms(t0)
  t0 = vim.uv.hrtime()
  km.sweep()
  r.sweep = ms(t0)
  t0 = vim.uv.hrtime()
  km.sweep()
  r.sweep_noop = ms(t0)
  r.nmaps = #vim.api.nvim_get_keymap("n")
  r.ok = vim.fn.maparg("<Space>гфф", "n") ~= "" and vim.fn.maparg("<Space>ьфф", "n") ~= ""
  return r
]])
D.row(
  "замер, мс",
  "400 × keymap.set",
  "дубли есть",
  ("без подмены %.2f; install %.3f; с подменой %.2f; sweep() 400 новых %.2f; sweep() повторно %.2f; привязок n %d"):format(
    t.base,
    t.install,
    t.hooked,
    t.sweep,
    t.sweep_noop,
    t.nmaps
  ),
  t.ok
)

D.stop()
vim.fn.delete(tmp, "rf")
D.finish()
