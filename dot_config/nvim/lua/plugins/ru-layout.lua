-- Neovim в русской раскладке: локальный плагин, грузится при старте (lazy = false)
-- раньше остальных, чтобы обёртки были на месте до загрузки чужих плагинов.
-- Подмена API привязок ставится ещё раньше — в lua/config/lazy.lua.
return {
  {
    name = "ru-layout",
    dir = vim.fn.stdpath("config") .. "/local/ru-layout",
    lazy = false,
    priority = 1000,
    config = function()
      require("ru-layout").setup()
    end,
  },
}
