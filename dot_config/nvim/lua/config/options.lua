-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.exrc = true
vim.opt.swapfile = false
vim.opt.whichwrap = "b,s,h,l,<,>,[,]"
vim.opt.winbar = "%=%m %f"
vim.opt.winbar = "%=%m %f"
vim.opt.laststatus = 3
vim.opt.cmdheight = 0
vim.opt.spelllang = "en_us,ru_ru"
vim.opt.spell = true
vim.g.snacks_animate = false
-- opts.rocks.hererocks = true
-- vim.g.lazyvim_python_lsp = "basedpyright"
-- vim.keymap.set("n", "<leader>uh", function()
--   vim.lsp.inlay_hint(0, nil)
-- end, { desc = "Toggle inlay hints" })
if vim.g.neovide then
  vim.g.neovide_padding_top = 6
  vim.g.neovide_padding_bottom = 6
  vim.g.neovide_padding_right = 6
  vim.g.neovide_padding_left = 6

  vim.opt.winblend = 40
  vim.opt.pumblend = 40
  -- vim.g.neovide_opacity = 0.9
  vim.g.neovide_floating_blur_amount_x = 3.0
  vim.g.neovide_floating_blur_amount_y = 3.0

  vim.g.neovide_cursor_trail_size = 0.0
  vim.g.neovide_cursor_animate_in_insert_mode = true
  vim.g.neovide_cursor_animate_command_line = true
  vim.g.neovide_cursor_animation_length = 0.3

  vim.g.neovide_cursor_vfx_mode = "ripple"

  vim.g.neovide_fullscreen = false
  vim.opt.linespace = 5

  vim.g.neovide_scale_factor = 1.0
  local change_scale_factor = function(delta)
    vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * delta
  end

  vim.keymap.set("n", "<C-=>", function()
    change_scale_factor(1.05)
  end, { desc = "Neovide scale up" })

  vim.keymap.set("n", "<C-->", function()
    change_scale_factor(0.95)
  end, { desc = "Neovide scale down" })

  vim.keymap.set("n", "<C-0>", function()
    vim.g.neovide_scale_factor = 1.0
  end, { desc = "Neovide no scale" })
end
