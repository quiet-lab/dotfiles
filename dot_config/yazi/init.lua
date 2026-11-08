require("full-border"):setup({
	-- Допустимые значения: ui.Border.PLAIN, ui.Border.ROUNDED
	type = ui.Border.ROUNDED,
})

-- Поставщик контекста для плагина herdr keys-help (docs/keys-help.md, D2 и D9 изменения
-- herdr-keys-help). Пишет запись `yazi-<pid>.json` в каталог панели herdr: при запуске и при
-- смене слоя (mgr, tasks, spot, pick, input, confirm, cmp, help). Работает только внутри
-- панели herdr (HERDR_PANE_ID), без таймеров и опроса.
--
-- Слой меняется без сообщений DDS, но каждая смена слоя перерисовывает интерфейс, а во время
-- перерисовки `cx.layer` доступен: проверка слоя встроена в Root:redraw и пишет запись, только
-- если слой изменился. Выхода из yazi Lua не видит (процесс завершается без события), поэтому
-- запись снимает просмотрщик по pidfd процесса, указанного в записи.
do
	local pane = os.getenv("HERDR_PANE_ID")
	local runtime = os.getenv("XDG_RUNTIME_DIR")
	if pane and pane ~= "" and runtime and runtime ~= "" then
		local stat = io.open("/proc/self/stat", "r")
		local pid = stat and stat:read("*l"):match("^(%d+)")
		if stat then
			stat:close()
		end
		local dir = runtime .. "/herdr-keys-help/panes/" .. pane

		-- Слои, у которых есть таблица клавиш в манифесте; остальные (which, notify, app)
		-- не меняют контекст.
		local known = { mgr = true, tasks = true, spot = true, pick = true, input = true, confirm = true, cmp = true, help = true }
		local path = dir .. "/yazi-" .. tostring(pid) .. ".json"
		local last = nil

		local function write_record(layer)
			if layer == last then
				return
			end
			-- Запись целиком одним write: просмотрщик читает по IN_CLOSE_WRITE.
			local file = io.open(path, "w")
			if not file then
				return
			end
			last = layer
			file:write(
				string.format(
					'{"v":1,"program":"yazi","mode":"%s","pid":%s,"state":"active","command":null,"table":null,"server":null,"env":{}}',
					layer,
					pid
				)
			)
			file:close()
		end

		if pid then
			-- Единственный внешний процесс за всё время работы: создание каталога панели.
			os.execute("mkdir -p " .. ya.quote(dir))
			write_record("mgr")

			local redraw = Root.redraw
			function Root:redraw()
				local layer = tostring(cx.layer)
				if known[layer] then
					write_record(layer)
				end
				return redraw(self)
			end
		end
	end
end
