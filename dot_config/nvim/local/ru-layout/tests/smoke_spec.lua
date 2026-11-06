-- Дымовой тест на настоящей конфигурации Neovim (LazyVim, плагины из
-- ~/.local/share/nvim/lazy; сети и установки плагинов не требуется).
-- По умолчанию читается конфигурация из дерева исходника (dot_config/nvim этого
-- репозитория), при RU_LAYOUT_SMOKE_CONFIG=home — применённая ~/.config/nvim.
-- Запуск: cd <корень плагина> && nvim -l tests/smoke_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

local cfg = vim.fn.fnamemodify(D.root, ":h:h") -- .../dot_config/nvim
if vim.env.RU_LAYOUT_SMOKE_CONFIG == "home" then
  cfg = vim.fn.expand("~/.config/nvim")
end
D.start({ config = cfg })

-- Без присоединённого интерфейса событие VeryLazy не наступает: нужные плагины
-- загружаются явно (lazy.load вызывает те же User LazyLoad, что и при запуске).
D.lua([[
  require("lazy").load({ plugins = { "flash.nvim", "which-key.nvim", "snacks.nvim" } })
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
]])

local msgs = D.lua("return vim.api.nvim_exec2('messages', { output = true }).output")
local bad = {}
for l in msgs:gmatch("[^\n]+") do
  if l:match("^E%d+") or l:lower():match("ru%-layout") or l:match("Error") or l:match("stack traceback") then
    bad[#bad + 1] = l
  end
end
D.check("после старта в :messages нет ошибок", {}, bad)

D.check("langmap задан", true, D.lua("return #vim.o.langmap > 0"))
D.check("ы в n — Flash", "Flash", D.lua("return vim.fn.maparg('ы', 'n', false, true).desc"))
D.check("s в n — Flash", "Flash", D.lua("return vim.fn.maparg('s', 'n', false, true).desc"))
local ff = D.lua("return vim.fn.maparg('<leader>ff', 'n', false, true).desc")
D.check("<leader>аа — как <leader>ff", ff, D.lua("return vim.fn.maparg('<leader>аа', 'n', false, true).desc"))
D.check("<leader>ff непуст", true, ff ~= nil and ff ~= "")

local st = D.lua([[
  local s = require("ru-layout.plugins").status
  return { wk = s["which-key.nvim"], sn = s["snacks.nvim"] }
]])
D.check("plugins.status: which-key обёрнут", true, st.wk == true)
D.check("plugins.status: snacks обёрнут", true, st.sn == true)

-- Жц<CR> в буфере acwrite с BufWriteCmd вызывает запись.
D.lua([[
  _G.W = 0
  vim.cmd("enew")
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    pattern = "acw://*",
    callback = function() _G.W = _G.W + 1; vim.bo.modified = false end,
  })
  vim.cmd("file acw://smoke")
  vim.bo.buftype = "acwrite"
  vim.bo.modified = true
]])
D.input("Жц<CR>")
D.sync()
D.check("Жц<CR> пишет буфер acwrite", 1, D.lua("return _G.W"))

-- ыпр в русском тексте запускает flash: метки в пространстве имён flash.
D.set_lines({
  "Привет, пример программы проверяет правку",
  "прямо проверка и проект",
})
D.input("<Esc>ы")
D.input("пр")
D.sync()
local marks = D.lua([[
  local ns = vim.api.nvim_get_namespaces()["flash"]
  if not ns then return -1 end
  return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
]])
D.row("ыпр запускает flash", "ыпр", "extmarks flash > 0", marks, type(marks) == "number" and marks > 0)
D.input("<Esc>")
D.sync()

D.stop()
D.finish()
