return {
  {
    "olimorris/onedarkpro.nvim",
    opts = function()
      local color = require("onedarkpro.helpers")
      local colors = color.get_colors("vaporwave")
      return {
        priority = 1000, -- Ensure it loads first
        colors = { vaporwave = { bg = "#000000" } },
        highlights = {
          Comment = { italic = true, fg = colors.gray },
          Constant = { bold = true },
          Identifier = { fg = "#ffffff", bold = true, italic = true },
          String = { italic = true },
          Conditional = { fg = colors.green, bold = true, italic = true },
          Keyword = { fg = colors.green, bold = true },
          Exception = { fg = colors.yellow, bold = true },
        },
      }
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "vaporwave",
    },
  },
}
