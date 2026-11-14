-- Дерево агентов Claude Code в herdr: местный плагин claudr.nvim, команда :Claudr.
-- Без каталога плагина спецификация отключена и запуск Neovim не затрагивается.
local dir = vim.fn.expand("~/work/pets/claudr.nvim")

return {
  {
    name = "claudr.nvim",
    dir = dir,
    enabled = vim.uv.fs_stat(dir) ~= nil,
    cmd = "Claudr",
    keys = {
      { "<leader>at", "<cmd>Claudr tree<cr>", desc = "Claudr: дерево агентов" },
    },
    opts = {},
  },
}
