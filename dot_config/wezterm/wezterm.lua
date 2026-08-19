local wezterm = require("wezterm")
local act = wezterm.action

local config = {}
-- Use config builder object if possible
if wezterm.config_builder then
	config = wezterm.config_builder()
end

-- Settings
-- config.color_scheme = "deep dive"
config.color_scheme = "onedarkpro_onedark"

-- config.font = wezterm.font("IosevkaTermSlab NF", { weight = "ExtraLight", stretch = "Normal", style = "Normal" })
--config.font = wezterm.font("Iosevka", { weight = "ExtraLight", stretch = "Normal", style = "Normal" })

config.font_size = 15.10
config.line_height = 1.4
config.freetype_load_flags = "NO_HINTING"
config.font = wezterm.font_with_fallback({
	{
		family = "IosevkaTermSlab NF", -- Укажите ваш основной шрифт
		-- weight = "Light",
		stretch = "Normal",
		style = "Normal",

		-- Параметр baseline принимает пиксели (например, "2px" или "-2px")
		-- или проценты ("10%"). Попробуйте сдвинуть вниз:
		-- baseline = "-5px",
	},
	-- Сюда можно добавить резервные шрифты (fallback)
})
config.window_background_opacity = 1.0
config.window_decorations = "RESIZE"
config.window_close_confirmation = "AlwaysPrompt"
config.scrollback_lines = 3000
config.default_workspace = "home"

-- Dim inactive panes
config.inactive_pane_hsb = {
	saturation = 0.4,
	brightness = 0.6,
}

config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}

config.ssh_domains = {
	{ name = "webim", remote_address = "10.200.115.216", username = "mne" },
	{ name = "dev", remote_address = "10.200.115.214", username = "mne" },
	{ name = "feature", remote_address = "10.200.115.217", username = "mne" },
}
-- Keys
-- config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }
-- config.keys = {
-- 	-- Send C-a when pressing C-a twice
-- 	{ key = "a", mods = "LEADER", action = act.SendKey({ key = "a", mods = "CTRL" }) },
-- 	{ key = "c", mods = "LEADER", action = act.ActivateCopyMode },
--
-- 	-- Pane keybindings
-- 	{ key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
-- 	-- SHIFT is for when caps lock is on
-- 	{ key = "|", mods = "LEADER|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
-- 	{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
-- 	{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
-- 	{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
-- 	{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
-- 	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
-- 	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },
-- 	{ key = "s", mods = "LEADER", action = act.RotatePanes("Clockwise") },
-- 	-- We can make separate keybindings for resizing panes
-- 	-- But Wezterm offers custom "mode" in the name of "KeyTable"
-- 	{ key = "r", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
--
-- 	-- Tab keybindings
-- 	{ key = "n", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
-- 	{ key = "[", mods = "LEADER", action = act.ActivateTabRelative(-1) },
-- 	{ key = "]", mods = "LEADER", action = act.ActivateTabRelative(1) },
-- 	{ key = "t", mods = "LEADER", action = act.ShowTabNavigator },
-- 	-- Key table for moving tabs around
-- 	{ key = "m", mods = "LEADER", action = act.ActivateKeyTable({ name = "move_tab", one_shot = false }) },
--
-- 	-- Lastly, workspace
-- 	{ key = "w", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
-- }
-- I can use the tab navigator (LDR t), but I also want to quickly navigate tabs with index
-- for i = 1, 9 do
-- 	table.insert(config.keys, {
-- 		key = tostring(i),
-- 		mods = "LEADER",
-- 		action = act.ActivateTab(i - 1),
-- 	})
-- end

-- config.key_tables = {
-- 	resize_pane = {
-- 		{ key = "h", action = act.AdjustPaneSize({ "Left", 1 }) },
-- 		{ key = "j", action = act.AdjustPaneSize({ "Down", 1 }) },
-- 		{ key = "k", action = act.AdjustPaneSize({ "Up", 1 }) },
-- 		{ key = "l", action = act.AdjustPaneSize({ "Right", 1 }) },
-- 		{ key = "Escape", action = "PopKeyTable" },
-- 		{ key = "Enter", action = "PopKeyTable" },
-- 	},
-- 	move_tab = {
-- 		{ key = "h", action = act.MoveTabRelative(-1) },
-- 		{ key = "j", action = act.MoveTabRelative(-1) },
-- 		{ key = "k", action = act.MoveTabRelative(1) },
-- 		{ key = "l", action = act.MoveTabRelative(1) },
-- 		{ key = "Escape", action = "PopKeyTable" },
-- 		{ key = "Enter", action = "PopKeyTable" },
-- 	},
-- }

-- Tab bar
-- I don't like the look of "fancy" tab bar
config.use_fancy_tab_bar = false
config.status_update_interval = 1000
wezterm.on("update-right-status", function(window, pane)
	-- Workspace name
	local stat = window:active_workspace()
	-- It's a little silly to have workspace name all the time
	-- Utilize this to display LDR or current key table name
	if window:active_key_table() then
		stat = window:active_key_table()
	end
	if window:leader_is_active() then
		stat = "LDR"
	end

	-- Current working directory
	local basename = function(s)
		-- Nothign a little regex can't fix
		if s then
			local str = tostring(s)
			local t = type(str)
			if t == "string" then
				return string.gsub(str, "(.*[/\\])(.*)", "%2")
			elseif t == "userdata" then
				print(s)
			end
		end
		return ""
	end
	local url = pane:get_current_working_dir()
	local host = ""
	local path = ""
	if url then
		host = url.host or "local"
		path = url.path or "$HOME"
	end
	-- Current command
	local cmd = basename(pane:get_foreground_process_name())

	-- Time
	local time = wezterm.strftime("%H:%M")

	-- Let's add color to one of the components
	window:set_right_status(wezterm.format({
		-- Wezterm has a built-in nerd fonts
		{ Text = wezterm.nerdfonts.oct_table .. "  " .. stat },
		{ Text = " | " },
		{ Text = host .. " " .. wezterm.nerdfonts.md_folder .. "  " .. path },
		{ Text = " | " },
		{ Foreground = { Color = "FFB86C" } },
		{ Text = wezterm.nerdfonts.fa_code .. "  " .. cmd },
		"ResetAttributes",
		{ Text = " | " },
		{ Text = wezterm.nerdfonts.md_clock .. "  " .. time },
		{ Text = " |" },
	}))
end)

--  -- Функция-обработчик для добавления разделителей
--  wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
--    local title = " " .. tab.tab_index + 1 .. ": " .. tab.active_pane.title .. " "
--
--    -- Символ разделителя и его цвет (например, серый)
--    local separator = "|"
--    local separator_color = '#45475a'
--
--    -- Если это последняя вкладка, разделитель справа не нужен
--    if tab.is_active then
--      return {
--        { Background = { Color = config.colors.tab_bar.active_tab.bg_color } },
--        { Foreground = { Color = config.colors.tab_bar.active_tab.fg_color } },
--        { Text = title },
--        -- Отрисовка разделителя сразу за активной вкладкой
--        { Background = { Color = config.colors.tab_bar.background } },
--        { Foreground = { Color = separator_color } },
--        { Text = separator },
--      }
--    else
--      return {
--        { Background = { Color = config.colors.tab_bar.inactive_tab.bg_color } },
--        { Foreground = { Color = config.colors.tab_bar.inactive_tab.fg_color } },
--        { Text = title },
--        -- Отрисовка разделителя за неактивной вкладкой
--        { Background = { Color = config.colors.tab_bar.background } },
--        { Foreground = { Color = separator_color } },
--        { Text = separator },
--      }
--    end
--  end)

return config
