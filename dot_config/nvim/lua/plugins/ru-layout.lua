-- Neovim в русской раскладке: локальный плагин, грузится при старте (lazy = false)
-- раньше остальных, чтобы обёртки были на месте до загрузки чужих плагинов.
-- Подмена API привязок ставится ещё раньше — в lua/config/lazy.lua.
local dir = vim.fn.stdpath("config") .. "/local/ru-layout"
-- Без каталога модуля (частичный apply) спецификации нет; предупреждение уже выдал lua/config/lazy.lua.
if not vim.uv.fs_stat(dir) then
  return {}
end

return {
  {
    name = "ru-layout",
    dir = dir,
    lazy = false,
    priority = 1000,
    config = function()
      require("ru-layout").setup()
    end,
  },
}
