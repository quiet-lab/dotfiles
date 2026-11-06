-- Одноразовая конфигурация испытуемого nvim: конфигурация пользователя не читается.
-- В rtp и package.path попадают модули плагина (`require("ru-layout.*")`), оснастка
-- (`require("flashsnap")`) и плагины из EXP_PLUGINS (каталоги ~/.local/share/nvim/lazy).
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here, ":h:h")
local lazy = vim.fn.expand("~/.local/share/nvim/lazy/")
package.path = here .. "/?.lua;" .. root .. "/lua/?.lua;" .. package.path
vim.opt.rtp:remove(vim.fn.stdpath("config"))
vim.opt.rtp:prepend(root)
for _, p in ipairs(vim.split(vim.env.EXP_PLUGINS or "", ",", { trimempty = true })) do
  vim.opt.rtp:prepend(lazy .. p)
end
vim.o.swapfile = false
vim.o.shada = ""
vim.o.lines = 40
vim.o.columns = 120
vim.g.mapleader = " "
if vim.env.EXP_LANGMAP == "1" then
  vim.o.langmap = require("ru-layout.table").langmap
end
