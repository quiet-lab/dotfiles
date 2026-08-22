-- local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
--
-- parser_config.yuck = {
--   install_info = {
--     url = "https://github.com/tree-sitter-grammars/tree-sitter-yuck",
--     files = { "src/parser.c" },
--     branch = "main",
--   },
--   filetype = "yuck",
-- }

vim.filetype.add({
  extension = {
    yuck = "yuck",
  },
})

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  pattern = { "*.yuck" },
  callback = function(event)
    print(string.format("starting yuck;s for %s", vim.inspect(event)))
    vim.lsp.start({
      name = "YuckLs",
      -- cmd = { "dotnet", "/home/gitrepos/yuckls/YuckLS/dist/YuckLS.dll" }, --this must be where you cloned this repo to.
      cmd = { "yuckls" }, -- if installed from aur
      root_dir = vim.fn.getcwd(),
    })
  end,
})

-- vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
--   pattern = "*.yuck",
--   callback = function()
--     vim.lsp.start({
--       name = "yuck-lsp",
--       cmd = { "yuckls" }, -- Replace with your local executable name
--       root_dir = vim.fs.dirname(vim.fs.find({ "eww.yuck" }, { upward = true })[1]),
--     })
--   end,
-- })

return { { "eraserhd/parinfer-rust", build = "cargo build --release" } }
