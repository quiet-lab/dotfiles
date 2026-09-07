-- Конфиг wezterm для запуска консольных приложений из дашборда eww
-- (избранное, лаунчер): wezterm --config-file ~/.config/wezterm/apps.lua start -- <программа>.
-- Берёт основной конфиг и убирает то, что мешает окну-приложению: панель вкладок,
-- вопрос при закрытии, задержку выхода. Отдельный файл конфига означает отдельный
-- процесс wezterm-gui, так что окна приложений не мешают окнам терминала.
local wezterm = require("wezterm")
local config = dofile(wezterm.config_dir .. "/wezterm.lua")

config.enable_tab_bar = false
config.window_close_confirmation = "NeverPrompt"
config.exit_behavior = "Close"

return config
