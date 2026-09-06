-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "json", "jsonc", "markdown" },
  callback = function()
    vim.wo.conceallevel = 0
  end,
})
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.env" },
  callback = function()
    vim.diagnostic.enable(false, { bufnr = 0 })
  end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    local bg_normal = "#03060c"
    local bg_dark = "#000000"
    local fg_title = "#00ff77"
    local fg_focus = "#ffffff"
    local fg_border = "#996633"
    vim.api.nvim_set_hl(0, "MiniFilesNormal", { bg = bg_normal })
    vim.api.nvim_set_hl(0, "MiniFilesBorder", { bg = bg_dark, fg = fg_border })
    vim.api.nvim_set_hl(0, "MiniFilesTitle", { bg = bg_dark, fg = fg_title })
    vim.api.nvim_set_hl(0, "MiniFilesTitleFocused", { bg = bg_dark, fg = fg_focus })

    -- 2. Фикс для Snacks: переопределяем базовые float-группы,
    -- так как Snacks берет цвет фона именно отсюда
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = bg_normal })
    vim.api.nvim_set_hl(0, "FloatTitle", { bg = bg_dark, fg = fg_title })
    vim.api.nvim_set_hl(0, "FloatBorder", { bg = bg_dark, fg = fg_border })

    vim.api.nvim_set_hl(0, "SnacksPickerWinBar", { bg = bg_dark, fg = fg_border })
    vim.api.nvim_set_hl(0, "SnacksPickerWinBarTitle", { bg = bg_dark, fg = fg_title })

    -- Явные группы Snacks, убираем любое смешивание (nocombine)
    local snacks_groups = {
      "SnacksPicker",
      "SnacksPickerList", -- Фон основного списка (самое важное!)
      -- "SnacksPickerInput", -- Фон поля ввода
      "SnacksPickerPreview", -- Фон правого превью
    }

    for _, group in ipairs(snacks_groups) do
      vim.api.nvim_set_hl(0, group, { bg = bg_normal, nocombine = true })
    end

    -- Границы для Snacks окон
    local snacks_borders = {
      "SnacksPickerInput", -- Фон поля ввода
      "SnacksPickerBorder",
      "SnacksPickerInputBorder",
      "SnacksPickerPreviewBorder",
    }
    for _, group in ipairs(snacks_borders) do
      vim.api.nvim_set_hl(0, group, { bg = bg_dark, fg = fg_border, nocombine = true })
    end

    -- Текстовые элементы и заголовки
    vim.api.nvim_set_hl(0, "SnacksPickerLabel", { bg = bg_dark, fg = fg_title })
    vim.api.nvim_set_hl(0, "SnacksPickerPrompt", { fg = fg_focus })

    vim.api.nvim_set_hl(0, "SnacksPickerSelected", { bg = "#000000" })

    -- 4. СОБСТВЕННО ДЛЯ ЭКСПЛОРЕРА (Создаем кастомные черные группы)
    vim.api.nvim_set_hl(0, "SnacksExplorerNormal", { bg = bg_dark, nocombine = true })
    vim.api.nvim_set_hl(0, "SnacksExplorerBorder", { bg = bg_dark, fg = fg_border, nocombine = true })
    vim.api.nvim_set_hl(0, "SnacksLayoutBox", { bg = bg_dark, nocombine = true }) -- Убирает артефакты GUI подложки
  end,
})
