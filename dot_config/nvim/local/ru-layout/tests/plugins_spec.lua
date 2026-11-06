-- Обёртки плагинов, читающих клавиши: ru-layout.plugins (с настоящими плагинами из
-- ~/.local/share/nvim/lazy). Перенесены проверки D1 (which-key) и D5 (mini.surround,
-- mini.ai) проекта; добавлены mini.files, bufferline, snacks pick_win, neogit, neotest,
-- nvim-dap-ui, diffview.
-- Запуск: cd <корень плагина> && nvim -l tests/plugins_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

local function H()
  return D.lua("local h = _G.H; _G.H = {}; return h")
end
-- Ввод с выходом из ожидания аргумента, если команда его ждёт.
local function step(keys)
  D.input(keys)
  local st = D.sync()
  if st:match("^BLOCKING") then
    while D.mode().blocking do
      D.input("<Esc>")
    end
  end
  return st
end

-- Набор 1: which-key, mini.surround, mini.ai, mini.files — как в конфигурации:
-- keymap.install() до плагинов, затем plugins.setup() по уже загруженным.
D.start({ langmap = true, plugins = { "which-key.nvim", "mini.surround", "mini.ai", "mini.files" } })
D.lua([[
require("ru-layout.keymap").install()
_G.H = {}
vim.keymap.set("n", "<leader>ff", function() table.insert(_G.H, "<leader>ff") end, { desc = "Find Files" })
vim.keymap.set("n", "<leader>fr", function() table.insert(_G.H, "<leader>fr") end, { desc = "Recent" })
vim.keymap.set("n", "<F2>", function() _G.H[#_G.H + 1] = vim.fn.getcharstr() end)
require("which-key").setup({ delay = 0, notify = false })
require("mini.surround").setup({
  mappings = {
    add = "gsa", delete = "gsd", find = "gsf", find_left = "gsF",
    highlight = "gsh", replace = "gsr", update_n_lines = "gsn",
  },
})
require("mini.ai").setup({})
require("ru-layout.plugins").setup()
]])

D.check(
  "setup: обёртки загруженных плагинов",
  { ["mini.ai"] = true, ["mini.surround"] = true, ["which-key.nvim"] = true },
  D.lua("return require('ru-layout.plugins').status")
)

-- D1 which-key
D.reset({ "abc" })
step("<Space>аа")
D.row("D1 which-key: <Space>аа", "<Space>аа", { "<leader>ff" }, H())
D.reset({ "abc" })
step("<Space>fа")
D.row("D1 which-key: <Space>fа смешанный", "<Space>fа", { "<leader>ff" }, H())
D.reset({ "abc" })
step("<Space>ак")
D.row("D1 which-key: <Space>ак", "<Space>ак", { "<leader>fr" }, H())
D.reset({ "abc" })
step("<Space>ff")
D.row("D1 which-key: контроль <Space>ff", "<Space>ff", { "<leader>ff" }, H())
D.reset({ "abc" })
step("<F2>ы")
D.row("D1 getcharstr вне which-key не тронут", "<F2>ы", { "ы" }, H())

-- Окно which-key: дерево, по которому окно строит список, без кириллических ключей,
-- хотя дубли модуля keymap как привязки существуют.
D.reset({ "abc" })
D.check(
  "which-key: дубль <leader>аа существует как привязка",
  true,
  D.lua("return vim.fn.maparg(' аа', 'n') ~= ''")
)
D.check(
  "which-key: дерево окна без кириллицы, латинские ветви на месте",
  { cyr = {}, ff = true, fr = true },
  D.lua([[
local P = require("ru-layout.plugins")
local mode = require("which-key.buf").get({ mode = "n", update = true })
local cyr, seen = {}, {}
local function walk(node)
  for _, ch in ipairs(node:children()) do
    if P.has_cyrillic(ch.keys) then cyr[#cyr + 1] = ch.keys end
    seen[ch.keys] = true
    walk(ch)
  end
end
walk(mode.tree.root)
return { cyr = cyr, ff = seen["<Space>ff"] == true, fr = seen["<Space>fr"] == true }
]])
)

-- D5 mini.surround / mini.ai
D.case("D5 mini.surround пыфшцэ → 'one'", "пыфшцэ", { "'one' two" }, D.lines, { lines = { "one two" } })
D.case("D5 mini.surround пывэ → снять '", "пывэ", { "one two" }, D.lines, { lines = { "'one' two" } })
D.case("D5 mini.surround пыкэЭ → ' на \"", "пыкэЭ", { '"one" two' }, D.lines, { lines = { "'one' two" } })
D.case(
  "D5 mini.ai вшф (d i a — аргумент)",
  "fbвшф",
  { "foo(, baz) + 1" },
  D.lines,
  { lines = { "foo(bar, baz) + 1" } }
)
D.case("D5 mini.ai сшэ (c i ')", "fbсшэX<Esc>", { "a 'X' d" }, D.lines, { lines = { "a 'bc' d" } })
D.case("D5 mini.ai вша (d i f — вызов)", "fbвша", { "foo() + 1" }, D.lines, { lines = { "foo(bar) + 1" } })
D.case("D5 mini.ai мшэ (v i ') в x", "fbмшэв", { "a '' d" }, D.lines, { lines = { "a 'bc' d" } })
D.case(
  "D5 mini.ai вштэ (d i n ' — следующий)",
  "вштэ",
  { "a '' d" },
  D.lines,
  { lines = { "a 'bc' d" } }
)
D.case(
  "D5 контроль: латинский dia",
  "fbdia",
  { "foo(, baz) + 1" },
  D.lines,
  { lines = { "foo(bar, baz) + 1" } }
)
D.case("D5 контроль: gsaiw'", "gsaiw'", { "'one' two" }, D.lines, { lines = { "one two" } })
D.case("D5 контроль: ci' латиницей", "fbci'X<Esc>", { "a 'X' d" }, D.lines, { lines = { "a 'bc' d" } })

-- mini.files: настройка после plugins.setup() — обёртка по событию LazyLoad.
D.reset({ "" })
D.lua([[
require("mini.files").setup({})
vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "mini.files" })
_G.mf_root = vim.fn.tempname()
vim.fn.mkdir(_G.mf_root .. "/sub", "p")
MiniFiles.open(_G.mf_root, false)
]])
step("ьф")
D.check(
  "mini.files: ьф ставит закладку a",
  true,
  D.lua("local b = MiniFiles.get_explorer_state().bookmarks; return b.a ~= nil and b['ф'] == nil")
)
step("j")
D.lua("MiniFiles.go_in()")
step("эф")
D.check(
  "mini.files: эф переходит к закладке a",
  true,
  D.lua([[
local st = MiniFiles.get_explorer_state()
return vim.fs.normalize(st.branch[st.depth_focus]) == vim.fs.normalize(_G.mf_root)
]])
)
D.lua("MiniFiles.close(); vim.fn.delete(_G.mf_root, 'rf')")
D.stop()

-- Набор 2: bufferline, snacks, neogit, neotest, nvim-dap-ui, diffview.
D.start({
  langmap = true,
  plugins = {
    "plenary.nvim",
    "nvim-nio",
    "nvim-dap",
    "bufferline.nvim",
    "snacks.nvim",
    "neogit",
    "neotest",
    "nvim-dap-ui",
    "diffview.nvim",
  },
})
D.lua([[
require("ru-layout.keymap").install()
_G.H = {}
vim.o.termguicolors = true
require("bufferline").setup({})
require("snacks").setup({})
require("neotest").setup({ adapters = {} })
require("dapui").setup()
require("diffview").setup({})
require("neogit").setup({})
require("ru-layout.plugins").setup()
]])
D.check("setup: обёртки загруженных плагинов", {
  ["bufferline.nvim"] = true,
  ["diffview.nvim"] = true,
  neogit = true,
  neotest = true,
  ["nvim-dap-ui"] = true,
  ["snacks.nvim"] = true,
}, D.lua("return require('ru-layout.plugins').status"))
D.check(
  "обёртки установлены",
  { true, true, true, true, true },
  D.lua([[
local G = require("ru-layout.getchar")
return {
  (G.is_wrapped(require("bufferline.pick").choose_then)),
  (G.is_wrapped(require("snacks.picker.util").pick_win)),
  (G.is_wrapped(require("neotest.lib.ui").open_buf)),
  (G.is_wrapped(require("dapui.util").select_win)),
  (G.is_wrapped(require("diffview.utils").input_char)),
}
]])
)

D.lua([[
local function rec(v) _G.H[#_G.H + 1] = v end
-- Без подключённого интерфейса Neovim не перерисовывает строку вкладок, а буквы
-- буферам bufferline раздаёт при её отрисовке; оснастка вычисляет строку вкладок
-- сама вместо отложенной перерисовки ui.refresh().
require("bufferline.ui").refresh = function()
  vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true })
end
vim.keymap.set("n", "<F3>", function() require("bufferline").pick() end)
vim.keymap.set("n", "<F4>", function() _G.R = Snacks.picker.util.pick_win({}) end)
vim.keymap.set("n", "<F5>", function() require("neotest.lib.ui").open_buf(_G.B, 0, 0) end)
vim.keymap.set("n", "<F6>", function() _G.R = require("dapui.util").select_win() end)
vim.keymap.set("n", "<F7>", function() rec((require("diffview.utils").input_char(nil, {}))) end)
-- Меню neogit без репозитория: состояние с одним аргументом-переключателем «-f».
vim.keymap.set("n", "<F8>", function()
  local P = require("neogit.lib.popup")
  local inst = P.new({
    name = "test",
    args = { { id = "-f", key_prefix = "-", type = "switch" } },
    config = {},
    actions = {},
  })
  inst.toggle_switch = function(_, arg) rec(arg.id) end
  inst.refresh = function() end
  local m = inst:mappings()
  rec((require("ru-layout.getchar").is_wrapped(m.n["-"])))
  m.n["-"]()
end)
]])

local two_wins = "vim.cmd('silent! only | vsplit')"
local function win_is(n)
  return function()
    return D.lua("return _G.R == vim.api.nvim_tabpage_list_wins(0)[...]", n)
  end
end

D.case("bufferline: метка ф выбирает буфер alpha", "<F3>ф", "alpha.txt", function()
  return D.lua("return vim.fn.expand('%:t')")
end, { pre = "vim.cmd('silent! only | file zeta.txt | edit alpha.txt | edit beta.txt')" })
D.case("bufferline: контроль латиницей a", "<F3>a", "alpha.txt", function()
  return D.lua("return vim.fn.expand('%:t')")
end, { pre = "vim.cmd('silent! only | file zeta.txt | edit alpha.txt | edit beta.txt')" })
D.case(
  "snacks pick_win: метка ы выбирает второе окно",
  "<F4>ы",
  true,
  win_is(2),
  { pre = two_wins }
)
D.case("snacks pick_win: контроль латиницей s", "<F4>s", true, win_is(2), { pre = two_wins })
D.case("neotest open_buf: метка и — буфер во втором окне", "<F5>и", true, function()
  return D.lua("return vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_list_wins(0)[2]) == _G.B")
end, { pre = two_wins .. "; _G.B = vim.api.nvim_create_buf(true, false)" })
D.case("nvim-dap-ui select_win: метка и — второе окно", "<F6>и", true, win_is(2), { pre = two_wins })
D.case(
  "nvim-dap-ui select_win: метка И (верхний регистр)",
  "<F6>И",
  true,
  win_is(2),
  { pre = two_wins }
)
D.case("diffview input_char: ы → s", "<F7>ы", { "s" }, H)
D.case("neogit меню: -а включает переключатель -f", "<F8>а", { true, "-f" }, H)
D.case("neogit меню: контроль -f латиницей", "<F8>f", { true, "-f" }, H)

D.stop()
D.finish()
