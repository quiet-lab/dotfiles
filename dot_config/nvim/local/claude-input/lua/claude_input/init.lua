-- Буфер ввода Claude Code: содержимое буфера neovim повторяется в строке ввода
-- Claude Code через сокет herdr (pane.send_text); `:w` отправляет запрос.
-- Таймеров нет: всё по событиям сокета (docs/decisions/0007-no-timers.md).
local M = {}

local uv = vim.uv or vim.loop
local dialog = require("claude_input.dialog")

-- Очистка строки ввода Claude Code: i, Ctrl+U, Esc (кодировка kitty), ggdG, i, Backspace.
M.PREFIX = "i\21\27[27uggdGi\127"
M.RAW_LIMIT = 700
local PASTE_BEGIN = "\27[200~"
local PASTE_END = "\27[201~"
local BUF_NAME = "claude://input"
local DIALOG_NAME = "claude://dialog"

local state = {
	buf = nil,
	in_flight = false,
	dirty = false,
	waiting = false,
	sub = nil,
	pending_submit = false,
	error_shown = false,
	warned_pane = false,
	seq = 0,
	-- Сразу после успешного `:w` строка ввода Claude Code пуста.
	just_submitted = false,
	-- Буфер диалога (design.md изменения claude-dialog-buffer, E2–E6).
	dbuf = nil,
	mode = "input",
	watch = nil,
	watch_events = 0,
	d_busy = false,
	d_refresh = false,
	d_edit = false,
	d_write = false,
	-- Текст, переданный плагином в поле свободного ввода текущего вопроса.
	field_text = "",
	-- Буфер диалога был пуст после последней передачи текста в поле.
	seen_empty = true,
	-- Подпись экрана до отправки стрелок или Enter: пока экран с ней совпадает,
	-- Claude Code ещё не обработал клавиши, и решения по нему не принимаются.
	guard = nil,
	-- Подпись диалога, на который ответ отправлен по `:w`: пока экран с ней
	-- совпадает, буфер диалога не открывается снова (design.md изменения
	-- claude-input-dialog-close).
	answered = nil,
	-- Образец выделения, которого ждёт защита, и закрытие подписки на него.
	expect = nil,
	expect_close = nil,
	-- Подпись последнего разобранного экрана диалога (для отмены по Ctrl+C).
	last_sig = nil,
	-- Подпись кадра диалога, на котором уже совпал подвал строки ввода.
	prompt_seen = nil,
	-- Ctrl+C во время цепочки: Esc уходит после её конца.
	cancel_pending = false,
	-- Последний известный статус панели Claude Code (из событий подписки и pane.get).
	status = nil,
}

-- Текст запроса: сырой, если короткий и без управляющих символов, иначе в рамке bracketed paste.
function M.payload(lines)
	local text = table.concat(lines, "\n")
	if text == "" then
		return ""
	end
	-- Порог в единицах UTF-16, как длина строки JS в Claude Code.
	local units = vim.str_utfindex(text, "utf-16")
	local raw = units <= M.RAW_LIMIT and not text:find("[%z\1-\9\11-\31\127]")
	if raw then
		return text
	end
	return PASTE_BEGIN .. text .. PASTE_END
end

function M.request_text(lines)
	return M.PREFIX .. M.payload(lines)
end

local function socket_path()
	local p = vim.env.HERDR_SOCKET_PATH
	if p and p ~= "" then
		return p
	end
	return vim.fn.expand("~/.config/herdr/herdr.sock")
end

-- Разбор строки ответа: на выходе таблица или nil.
local function decode(line)
	local ok, res = pcall(vim.json.decode, line)
	if ok and type(res) == "table" then
		return res
	end
end

-- Запрос к сокету: cb(response|nil, err) вызывается в основном цикле neovim.
-- Для подписки on_line получает каждую следующую строку; возвращается закрытие соединения.
local function request(method, params, cb, on_line)
	state.seq = state.seq + 1
	local pipe = uv.new_pipe(false)
	local buf = ""
	local first = true
	local closed = false
	local function close()
		if not closed then
			closed = true
			pipe:read_stop()
			if not pipe:is_closing() then
				pipe:close()
			end
		end
	end
	local function finish(res, err)
		if first then
			first = false
			vim.schedule(function()
				cb(res, err)
			end)
		end
	end
	pipe:connect(socket_path(), function(cerr)
		if cerr then
			close()
			return finish(nil, cerr)
		end
		local line = vim.json.encode({ id = "ci" .. state.seq, method = method, params = params }) .. "\n"
		pipe:write(line, function(werr)
			if werr then
				close()
				finish(nil, werr)
			end
		end)
		pipe:read_start(function(rerr, data)
			if rerr then
				close()
				return finish(nil, rerr)
			end
			if data == nil then
				close()
				if first then
					finish(nil, "соединение закрыто без ответа")
				elseif on_line then
					vim.schedule(function()
						on_line(nil)
					end)
				end
				return
			end
			buf = buf .. data
			while true do
				local nl = buf:find("\n", 1, true)
				if not nl then
					break
				end
				local l = buf:sub(1, nl - 1)
				buf = buf:sub(nl + 1)
				if l ~= "" then
					local res = decode(l)
					if first then
						if on_line == nil then
							close()
						end
						if res and res.error then
							finish(nil, res.error.message or "ошибка herdr")
						elseif res then
							finish(res)
						else
							finish(nil, "ответ не разобран")
						end
					elseif on_line then
						vim.schedule(function()
							on_line(res)
						end)
					end
				end
			end
		end)
	end)
	return close
end
M._request = request

-- Текст сырыми байтами, затем Enter клавишей: сырой `\r` строка ввода
-- Claude Code 2.1.319 запросом не считает, а клавишу herdr кодирует по режиму
-- клавиатуры терминала. Порядок байтов сохраняется: запросы идут друг за другом.
local function send_then_enter(pane, text, enter, cb)
	local function press()
		if not enter then
			return cb()
		end
		request("pane.send_keys", { pane_id = pane, keys = { "enter" } }, function(_, err)
			cb(err)
		end)
	end
	if text == "" then
		return press()
	end
	request("pane.send_text", { pane_id = pane, text = text }, function(_, err)
		if err then
			return cb(err)
		end
		press()
	end)
end

local function pane_id()
	local p = vim.env.CLAUDE_INPUT_PANE
	if p and p ~= "" then
		return p
	end
end

local function buf_lines()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		return vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
	end
	return {}
end

-- cb(status|nil, err)
local function get_status(pane, cb)
	request("pane.get", { pane_id = pane }, function(res, err)
		if err or not res then
			return cb(nil, err or "нет ответа")
		end
		local p = res.result and res.result.pane
		cb(p and p.agent_status or "unknown")
	end)
end
M._get_status = get_status

local function report_error(err)
	if not state.error_shown then
		state.error_shown = true
		vim.notify("claude-input: сокет herdr: " .. tostring(err), vim.log.levels.ERROR)
	end
end

local schedule_send

-- Конец цепочки: если за время её работы буфер менялся, начинается новая.
local function chain_done()
	state.in_flight = false
	if state.pending_submit then
		state.pending_submit = false
		M.submit()
	elseif state.dirty and not state.waiting then
		state.dirty = false
		schedule_send()
	end
end

local function open_subscription(pane)
	state.waiting = true
	local close
	close = request("events.subscribe", {
		subscriptions = { { type = "pane.agent_status_changed", pane_id = pane } },
	}, function(_, err)
		if err then
			state.waiting = false
			state.sub = nil
			if close then
				close()
			end
			return report_error(err)
		end
		-- Статус мог покинуть blocked до установки подписки.
		get_status(pane, function(status)
			if not state.waiting or state.sub ~= close or not status or status == "blocked" then
				return
			end
			close()
			state.sub = nil
			state.waiting = false
			if state.dirty then
				state.dirty = false
				schedule_send()
			end
		end)
	end, function(ev)
		if not state.waiting then
			return
		end
		if ev == nil then
			state.waiting = false
			state.sub = nil
			return
		end
		local data = ev.data
		local status = type(data) == "table" and data.agent_status or nil
		if ev.event == "pane.agent_status_changed" and status and status ~= "blocked" then
			if state.sub then
				state.sub()
			end
			state.sub = nil
			state.waiting = false
			if state.dirty then
				state.dirty = false
				schedule_send()
			end
		end
	end)
	state.sub = close
end

schedule_send = function()
	local pane = pane_id()
	if not pane then
		return
	end
	-- Подписка буфера диалога, потерянная при обрыве, поднимается правкой буфера ввода.
	if not state.watch and M.watch then
		M.watch()
	end
	if state.in_flight or state.waiting then
		state.dirty = true
		return
	end
	-- После `:w` строка ввода уже пуста: лишний Esc очистки закрыл бы открытый
	-- запросом диалог Claude Code (например, /help).
	if state.just_submitted and M.payload(buf_lines()) == "" then
		return
	end
	state.in_flight = true
	get_status(pane, function(status, err)
		if err then
			state.in_flight = false
			state.pending_submit = false
			return report_error(err)
		end
		if state.pending_submit then
			state.in_flight = false
			state.pending_submit = false
			return M.submit()
		end
		if status == "blocked" then
			state.in_flight = false
			state.dirty = true
			if not state.waiting then
				open_subscription(pane)
			end
			return
		end
		local payload = M.payload(buf_lines())
		request("pane.send_text", { pane_id = pane, text = M.PREFIX .. payload }, function(_, serr)
			if serr then
				state.in_flight = false
				return report_error(serr)
			end
			state.error_shown = false
			state.just_submitted = false
			chain_done()
		end)
	end)
end
M.schedule_send = schedule_send

-- Отправка запроса (`:w`).
function M.submit()
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local lines = buf_lines()
	local empty = true
	for _, l in ipairs(lines) do
		if l ~= "" then
			empty = false
			break
		end
	end
	if empty then
		vim.bo[buf].modified = false
		return
	end
	local pane = pane_id()
	if not pane then
		return
	end
	if state.in_flight then
		state.pending_submit = true
		return
	end
	state.in_flight = true
	get_status(pane, function(status, err)
		if err then
			state.in_flight = false
			return report_error(err)
		end
		if status == "blocked" then
			state.in_flight = false
			vim.notify("Claude Code ждёт ответа в диалоге", vim.log.levels.WARN)
			return
		end
		send_then_enter(pane, M.request_text(buf_lines()), true, function(serr)
			if serr then
				state.in_flight = false
				return report_error(serr)
			end
			state.error_shown = false
			state.just_submitted = true
			if state.waiting then
				if state.sub then
					state.sub()
				end
				state.sub = nil
				state.waiting = false
			end
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
				vim.bo[buf].modified = false
			end
			state.dirty = false
			chain_done()
		end)
	end)
end

-- Экран панели Claude Code: cb(text|nil, err).
local function read_screen(pane, cb)
	request("pane.read", { pane_id = pane, source = "detection" }, function(res, err)
		if err or not res then
			return cb(nil, err or "нет ответа")
		end
		local r = res.result and res.result.read
		cb(r and r.text or "")
	end)
end

local function set_lines_clean(buf, lines)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modified = false
	end
end

-- Окно, показывающее буфер from, переводится на буфер to.
-- false — буфер from нигде не показан, окна не меняются.
local function swap_window(from, to)
	local win = vim.fn.win_findbuf(from)[1]
	if not win then
		return false
	end
	vim.api.nvim_win_set_buf(win, to)
	return true
end

-- Визуальный перенос строк в окнах, показывающих буфер модуля: текст буфера
-- не меняется. Настройка — на окно, не глобально: по каждому показу буфера
-- в любом окне состав окон сверяется (окно текущим может не быть), у окна
-- с буфером модуля опции включаются, а у окна, из которого буфер ушёл,
-- возвращаются прежние значения; соседние буферы настройку не наследуют.
local WRAP_OPTS = { "wrap", "linebreak", "breakindent" }

local function sync_wrap()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local b = vim.api.nvim_win_get_buf(win)
		local ours = b == state.buf or b == state.dbuf
		local saved = vim.w[win].claude_input_wrap_saved
		if ours and not saved then
			saved = {}
			for _, o in ipairs(WRAP_OPTS) do
				-- Окно, созданное делением окна модуля, унаследовало уже включённые
				-- опции: возвращается значение по умолчанию, а не унаследованное.
				saved[o] = vim.wo[win][o] and vim.go[o]
				vim.wo[win][o] = true
			end
			vim.w[win].claude_input_wrap_saved = saved
		elseif not ours and saved then
			for o, v in pairs(saved) do
				vim.wo[win][o] = v
			end
			vim.w[win].claude_input_wrap_saved = nil
		end
	end
end

local function wrap_on_show()
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = vim.api.nvim_create_augroup("claude_input_wrap", { clear = true }),
		callback = sync_wrap,
	})
end

local d_step

-- Подсказка диалога — окно разделения справа от диалога:
-- строки «клавиша → описание», заголовок — шаг карточки. Сам which-key
-- не вызывается: его окно живёт только пока ждёт клавишу.
local HINT_NS = vim.api.nvim_create_namespace("claude_input_hint")
local HINT_SEP = " → "

-- Заголовок и строки {клавиша, описание, выделен}.
local function hint_lines(d)
	local head
	if d.review then
		head = "Обзор ответов"
	elseif d.tabs then
		head = string.format("Вопрос %d из %d", math.min(d.tabs.done + 1, d.tabs.total), d.tabs.total)
	else
		head = "Диалог"
	end
	local rows = {}
	for _, r in ipairs(d.rows) do
		table.insert(rows, { r.num and tostring(r.num) or "", (r.selected and "❯ " or "  ") .. r.label, r.selected })
	end
	table.insert(rows, { "S-CR", "подтвердить" })
	table.insert(rows, { "S-Space", "подтвердить" })
	table.insert(rows, { "C-c", "отменить диалог" })
	return head, rows
end
M._hint_lines = hint_lines

local hint = { win = nil, buf = nil, d = nil, dwin = nil }

-- Группа which-key, если она есть, иначе запасная.
local function hl_group(wk, fallback)
	return vim.fn.hlexists(wk) == 1 and wk or fallback
end

local function hint_close()
	hint.d = nil
	if hint.win and vim.api.nvim_win_is_valid(hint.win) then
		pcall(vim.api.nvim_win_close, hint.win, true)
	end
	if hint.buf and vim.api.nvim_buf_is_valid(hint.buf) then
		pcall(vim.api.nvim_buf_delete, hint.buf, { force = true })
	end
	hint.win, hint.buf, hint.dwin = nil, nil, nil
end

-- Ширина окна подсказки: пятая часть ширины панели (1:4 к окну диалога),
-- не меньше HINT_MIN_WIDTH; в узкой панели подсказке 20 столбцов, остаток
-- достаётся диалогу.
local HINT_MIN_WIDTH = 20
local function hint_width(total)
	return math.max(HINT_MIN_WIDTH, math.floor(total / 5))
end
M._hint_width = hint_width

-- Окно разделения справа от окна диалога: в панели в 13 строк виртуальные
-- строки отнимали бы место у текста ответа. Окно не берёт фокус и ввод;
-- заголовок — в его winbar. Ширина считается от суммы ширин обоих окон
-- (с вертикальным разделителем), поэтому пересчёт не накапливает сдвиг.
local function hint_render()
	local d = hint.d
	local dbuf = state.dbuf
	local dwin = dbuf and vim.api.nvim_buf_is_valid(dbuf) and vim.fn.win_findbuf(dbuf)[1]
	if not d or not dwin then
		return
	end
	local head, rows = hint_lines(d)
	local open = hint.win and vim.api.nvim_win_is_valid(hint.win)
	if open and hint.dwin ~= dwin then
		pcall(vim.api.nvim_win_close, hint.win, true)
		open = false
	end
	local dw = vim.api.nvim_win_get_width(dwin)
	local total = open and dw + vim.api.nvim_win_get_width(hint.win) + 1 or dw
	local width = hint_width(total)
	local dh = vim.api.nvim_win_get_height(dwin)
	-- Не помещается по высоте (строка winbar занята заголовком): клавиши
	-- внизу остаются, из пунктов выбирается окно вокруг выделенного.
	local maxh = math.max(1, dh - 1)
	if #rows > maxh then
		local n_items = #d.rows
		local footer = {}
		for i = n_items + 1, #rows do
			table.insert(footer, rows[i])
		end
		local avail = maxh - #footer
		if avail < 1 then
			rows = vim.list_slice(footer, #footer - maxh + 1)
		else
			local first = math.max(1, math.min((d.sel or 1) - math.floor(avail / 2), n_items - avail + 1))
			rows = vim.list_slice(rows, first, first + avail - 1)
			vim.list_extend(rows, footer)
		end
	end
	local kw = 1
	for _, r in ipairs(rows) do
		kw = math.max(kw, vim.fn.strdisplaywidth(r[1]))
	end
	local lines = {}
	for _, r in ipairs(rows) do
		table.insert(lines, string.rep(" ", kw - vim.fn.strdisplaywidth(r[1])) .. r[1] .. HINT_SEP .. r[2])
	end
	if not (hint.buf and vim.api.nvim_buf_is_valid(hint.buf)) then
		hint.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[hint.buf].bufhidden = "wipe"
	end
	vim.api.nvim_buf_set_lines(hint.buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(hint.buf, HINT_NS, 0, -1)
	local g_key = hl_group("WhichKey", "Special")
	local g_sep = hl_group("WhichKeySeparator", "Comment")
	local g_desc = hl_group("WhichKeyDesc", "Normal")
	for i, r in ipairs(rows) do
		local kend = kw + #r[1] - vim.fn.strdisplaywidth(r[1])
		local function mark(c0, c1, g)
			vim.api.nvim_buf_set_extmark(hint.buf, HINT_NS, i - 1, c0, { end_col = c1, hl_group = g })
		end
		mark(0, kend, g_key)
		mark(kend, kend + #HINT_SEP, g_sep)
		mark(kend + #HINT_SEP, #lines[i], r[3] and "CursorLine" or g_desc)
	end
	if not open then
		hint.win = vim.api.nvim_open_win(hint.buf, false, { split = "right", win = dwin, width = width })
		hint.dwin = dwin
		local wo = vim.wo[hint.win]
		wo.wrap = false
		wo.number, wo.relativenumber, wo.list = false, false, false
		wo.signcolumn, wo.foldcolumn, wo.colorcolumn, wo.statuscolumn = "no", "0", "", ""
		wo.cursorline, wo.spell, wo.winfixwidth = false, false, true
		wo.winhighlight = "Normal:" .. hl_group("WhichKeyNormal", "NormalFloat")
	elseif vim.api.nvim_win_get_width(hint.win) ~= width then
		vim.api.nvim_win_set_width(hint.win, width)
	end
	vim.wo[hint.win].winbar = "%#" .. hl_group("WhichKeyTitle", "Title") .. "# " .. head:gsub("%%", "%%%%") .. " "
end

local function show_hint(d)
	hint.d = d
	if d then
		hint_render()
	else
		hint_close()
	end
end

M._show_hint = show_hint
M._hint_win = function()
	return hint.win
end
M._hint_buf = function()
	return hint.buf
end

local function ensure_dialog_buf()
	if state.dbuf and vim.api.nvim_buf_is_valid(state.dbuf) then
		return state.dbuf
	end
	-- Буфер диалога не входит в список буферов: в строке буферов его нет,
	-- окно на него переводит только модуль.
	-- Буфер с тем же именем мог остаться, если удаление не удалось.
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(b) == DIALOG_NAME then
			if not pcall(vim.api.nvim_buf_delete, b, { force = true }) then
				pcall(vim.api.nvim_buf_set_name, b, DIALOG_NAME .. "#" .. b)
			end
		end
	end
	local buf = vim.api.nvim_create_buf(false, false)
	state.dbuf = buf
	vim.api.nvim_buf_set_name(buf, DIALOG_NAME)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].swapfile = false
	vim.bo[buf].bufhidden = "hide"
	wrap_on_show()
	vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = vim.api.nvim_create_augroup("claude_input_hint", { clear = true }),
		callback = function()
			pcall(hint_render)
		end,
	})
	-- Окно диалога могло появиться после показа подсказки.
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = "claude_input_hint",
		buffer = buf,
		callback = function()
			pcall(hint_render)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		group = "claude_input_hint",
		buffer = buf,
		callback = hint_close,
	})
	-- Пустой буфер отмечается на каждом изменении: несколько клавиш одного куска
	-- (Ctrl+U и цифра) дают одно событие TextChangedI уже без пустого состояния.
	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, b)
			if vim.api.nvim_buf_line_count(b) == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == "" then
				state.seen_empty = true
			end
		end,
	})
	local group = vim.api.nvim_create_augroup("claude_input_dialog", { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
		group = group,
		buffer = buf,
		callback = function()
			M.dialog_changed()
		end,
	})
	-- Подтверждение выбора: :w, Shift+Enter и Shift+Пробел идут одним путём.
	local function confirm()
		vim.bo[buf].modified = false
		-- Правка, до которой TextChangedI ещё не дошло (клавиши одним пакетом),
		-- уходит раньше Enter тем же путём, что обычная правка.
		if vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] ~= "" or vim.api.nvim_buf_line_count(buf) > 1 then
			state.d_edit = true
		end
		state.d_write = true
		d_step()
	end
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = group,
		buffer = buf,
		callback = confirm,
	})
	-- Отмена диалога: Esc в Claude Code, окно сразу возвращается к вводу.
	local function cancel()
		local pane = pane_id()
		if not pane then
			return
		end
		state.d_edit = false
		state.d_write = false
		state.answered = state.last_sig
		M._show_input()
		if state.d_busy then
			-- Отправка цепочки уже идёт: Esc уходит после неё, порядок клавиш сохраняется.
			state.cancel_pending = true
			return
		end
		M._send_esc(pane)
	end
	vim.keymap.set(
		{ "i", "n" },
		"<C-c>",
		cancel,
		{ buffer = buf, desc = "claude-input: отменить диалог" }
	)
	for _, key in ipairs({ "<S-CR>", "<S-Space>" }) do
		vim.keymap.set(
			{ "i", "n" },
			key,
			confirm,
			{ buffer = buf, desc = "claude-input: подтвердить выбор" }
		)
	end
	return buf
end

-- Подписки pane.output_matched по ключу: на ключ одна подписка; по совпадению
-- (herdr шлёт его и сразу при подписке, если экран уже совпадает) или по обрыву
-- она закрывается и вызывает on_match. on_err — то же при ошибке подписки.
local watches = {}
M._watches = watches

local function watch_stop(key)
	local w = watches[key]
	if w then
		watches[key] = nil
		w.close()
	end
end

local function watch_match(key, regex, on_match, on_err)
	local pane = pane_id()
	if not pane then
		return
	end
	local cur = watches[key]
	if cur and cur.regex == regex then
		return
	end
	watch_stop(key)
	local w = { regex = regex }
	local function release(fire)
		if watches[key] ~= w then
			return
		end
		watches[key] = nil
		w.close()
		if fire then
			on_match()
		end
	end
	w.close = request("events.subscribe", {
		subscriptions = {
			{
				type = "pane.output_matched",
				pane_id = pane,
				source = "detection",
				match = { type = "regex", value = regex },
			},
		},
	}, function(_, err)
		if err then
			release(on_err)
		end
	end, function(ev)
		if ev == nil or ev.event == "pane.output_matched" then
			release(true)
		end
	end)
	watches[key] = w
end

-- Ожидание выделения state.expect: после него отложенное задание job
-- выполняется заново. Без образца задание ждёт следующей правки или события
-- подписки.
local function wait_expect(job)
	if not state.expect or watches.expect then
		return
	end
	watch_match("expect", state.expect, function()
		if job == "write" then
			state.d_write = true
		end
		state.d_edit = true
		d_step()
	end, true)
end

local function stop_expect()
	watch_stop("expect")
	state.expect = nil
end

-- Ожидание перехода карточки к следующему вопросу (строка вкладок с большим
-- числом отвеченных): буфер диалога остаётся открытым, пока карточка не
-- завершена, а после перехода цепочка заново читает экран. Ответ мог прийти
-- и из панели Claude Code.
local function card_watch(done)
	watch_match("card", dialog.card_regex(done), function()
		local dbuf = state.dbuf
		local lines = dbuf and vim.api.nvim_buf_is_valid(dbuf) and vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)
			or { "" }
		if #lines > 1 or lines[1] ~= "" then
			-- Набранное до перехода относится к следующему вопросу.
			state.d_edit = true
		else
			state.d_refresh = true
		end
		d_step()
	end)
end

-- Ожидание строки ввода Claude Code, пока открыт буфер диалога: herdr после
-- правки поля свободного ввода может держать статус idle до конца карточки,
-- поэтому закрытие диалога видно только по экрану. Совпадение при экране,
-- который всё ещё диалог, запоминается по подписи кадра: до смены кадра
-- подписка не повторяется, иначе подписка и чтение экрана шли бы по кругу.
local function prompt_watch()
	if state.prompt_seen ~= nil and state.prompt_seen == state.last_sig then
		return
	end
	watch_match("prompt", dialog.PROMPT_REGEX, function()
		state.prompt_seen = state.last_sig
		state.d_refresh = true
		d_step()
	end)
end

-- Правка буфера диалога.
function M.dialog_changed()
	local buf = state.dbuf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	state.d_edit = true
	d_step()
end

local function show_dialog()
	local dbuf = ensure_dialog_buf()
	set_lines_clean(dbuf, {})
	state.guard = nil
	stop_expect()
	state.prompt_seen = nil
	state.field_text = ""
	state.seen_empty = true
	state.mode = "dialog"
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) and swap_window(state.buf, dbuf) then
		vim.cmd("startinsert")
	end
end

local function show_input()
	state.mode = "input"
	state.guard = nil
	stop_expect()
	watch_stop("card")
	watch_stop("prompt")
	state.prompt_seen = nil
	state.field_text = ""
	local db = state.dbuf
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) and db then
		swap_window(db, state.buf)
	end
	-- Буфер диалога живёт только на время диалога: после него удаляется,
	-- следующий диалог создаёт его заново.
	state.dbuf = nil
	hint_close()
	if db and vim.api.nvim_buf_is_valid(db) then
		pcall(vim.api.nvim_buf_delete, db, { force = true })
	end
end

M._show_input = show_input

-- Решение по свежему экрану: job — "write", "edit" или "refresh".
-- done() завершает цепочку; send(keys) отправляет клавиши и затем завершает её.
local function d_decide(job, status, text, send, done)
	local d = text and dialog.parse(text)
	if
		d
		and state.mode == "dialog"
		and status ~= "blocked"
		and not dialog.on_free(d)
		and (status == "working" or (not d.tabs and not d.review))
	then
		-- Не blocked бывает только при выделенном поле свободного ввода (Д3);
		-- иначе экран — прежний кадр закрытого диалога. Карточку с вопросами
		-- herdr после правки поля может держать в idle до её конца: её экран
		-- остаётся диалогом.
		d = nil
	end
	if d then
		state.last_sig = dialog.signature(d)
	end
	if not d or (state.mode ~= "dialog" and status ~= "blocked") then
		if not d or status ~= "blocked" then
			-- Экран перестал быть диалогом или статус вышел из blocked:
			-- ответ принят, такой же диалог дальше новый.
			state.answered = nil
		end
		if state.mode == "dialog" then
			show_input()
		end
		return done()
	end
	if state.mode ~= "dialog" then
		if state.answered ~= nil and state.answered == dialog.signature(d) then
			-- Ответ на этот экран уже отправлен, Claude Code его не перерисовал.
			return done()
		end
		state.answered = nil
		show_dialog()
		show_hint(d)
		prompt_watch()
		if d.tabs and not d.review then
			card_watch(d.tabs.done)
		end
		return done()
	end
	local dbuf = state.dbuf
	local lines = vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)
	local content = table.concat(lines, "\n")
	local on_free = dialog.on_free(d)
	local sig = dialog.signature(d)
	local stale = state.guard ~= nil and state.guard == sig
	if not stale then
		state.guard = nil
		stop_expect()
	end
	if d.tabs and not d.review then
		card_watch(d.tabs.done)
	end
	if not stale then
		show_hint(d)
	end
	prompt_watch()
	if stale and (job == "edit" or (job == "write" and state.expect)) then
		-- Прежний экран: задание повторяется по событию выделения или при
		-- следующей правке; буфер не трогается.
		wait_expect(job)
		return done()
	end
	if job == "write" then
		local keys = dialog.submit_keys(d)
		set_lines_clean(dbuf, {})
		state.field_text = ""
		state.seen_empty = true
		if d.tabs and not d.review then
			-- Вопрос карточки: следующий вопрос и обзор отвечаются в том же буфере,
			-- окно к вводу не возвращается; до перехода экран прежний.
			state.guard = sig
			-- Правка до перехода ждёт его тем же образцом строки вкладок.
			state.expect = dialog.card_regex(d.tabs.done)
			return send(keys)
		end
		-- Ввод возвращается сразу, не дожидаясь смены экрана панели.
		show_input()
		state.answered = sig
		return send(keys)
	end
	if job ~= "edit" then
		return done()
	end
	local n = content:match("^%s*(%d+)%s*$")
	if n and (not on_free or state.field_text == "" or state.seen_empty) then
		n = tonumber(n)
		local dirty_field = on_free and (state.field_text ~= "" or d.free_text ~= "")
		local keys = dialog.digit_keys(d, n, dirty_field and M.PREFIX or nil)
		set_lines_clean(dbuf, {})
		state.seen_empty = true
		if dirty_field then
			state.field_text = ""
		end
		if keys and keys ~= "" then
			if keys ~= tostring(n) then
				-- Стрелки меняют выделение: до перерисовки экран прежний.
				state.guard = sig
				state.expect = dialog.selected_regex(d.rows[dialog.index(d, n)])
			end
			return send(keys)
		end
		return done()
	end
	if on_free then
		if content == state.field_text and content == d.free_text then
			return done()
		end
		state.field_text = content
		if content ~= "" then
			state.seen_empty = false
		end
		return send(M.PREFIX .. M.payload(lines))
	end
	return done()
end

-- Отмена диалога: Esc клавишей в панели Claude Code.
function M._send_esc(pane)
	request("pane.send_keys", { pane_id = pane, keys = { "esc" } }, function(_, err)
		if err then
			state.answered = nil
			report_error(err)
		end
	end)
end

-- Цепочка буфера диалога: статус, экран, решение, отправка; в полёте одна.
d_step = function()
	local pane = pane_id()
	if not pane or state.d_busy then
		return
	end
	-- Правка раньше записи: последний текст поля уходит до Enter.
	local job
	if state.d_edit then
		job = "edit"
		state.d_edit = false
	elseif state.d_write then
		job = "write"
		state.d_write = false
	elseif state.d_refresh then
		job = "refresh"
	else
		return
	end
	state.d_refresh = false
	state.d_busy = true
	if not state.watch then
		M.watch()
	end
	local function flush_cancel()
		if state.cancel_pending then
			state.cancel_pending = false
			M._send_esc(pane)
		end
	end
	local function done()
		state.d_busy = false
		flush_cancel()
		d_step()
	end
	local function fail(err)
		state.d_busy = false
		flush_cancel()
		-- Ответ мог не уйти: диалог должен открываться снова.
		state.answered = nil
		report_error(err)
	end
	local function with_status(cb)
		if state.status then
			return cb(state.status)
		end
		get_status(pane, function(status, err)
			if status then
				state.status = status
			end
			cb(status, err)
		end)
	end
	with_status(function(status, err)
		if err then
			return fail(err)
		end
		read_screen(pane, function(text, rerr)
			if rerr then
				return fail(rerr)
			end
			d_decide(job, status, text, function(keys)
				local enter = keys:sub(-#dialog.ENTER) == dialog.ENTER
				if enter then
					keys = keys:sub(1, -#dialog.ENTER - 1)
				end
				send_then_enter(pane, keys, enter, function(serr)
					if serr then
						return fail(serr)
					end
					state.error_shown = false
					done()
				end)
			end, done)
		end)
	end)
end

-- Постоянная подписка на смену статуса панели Claude Code (E2).
function M.watch()
	local pane = pane_id()
	if not pane or state.watch then
		return
	end
	state.watch_events = 0
	local close
	close = request("events.subscribe", {
		subscriptions = { { type = "pane.agent_status_changed", pane_id = pane } },
	}, function(_, err)
		if err then
			if state.watch == close then
				state.watch = nil
			end
			close()
			return report_error(err)
		end
		-- Статус до подписки неизвестен: следующая цепочка спросит pane.get.
		state.status = nil
		state.d_refresh = true
		d_step()
	end, function(ev)
		if state.watch ~= close then
			return
		end
		if ev == nil then
			state.watch = nil
			state.status = nil
			-- Обрыв после событий — подписка открывается заново один раз;
			-- обрыв без событий — следующая правка буфера диалога.
			if state.watch_events > 0 then
				M.watch()
			end
			return
		end
		if ev.event == "pane.agent_status_changed" then
			state.watch_events = state.watch_events + 1
			local data = ev.data
			state.status = type(data) == "table" and data.agent_status or nil
			if state.status ~= "blocked" then
				-- Статус вышел из blocked: ответ принят, такой же диалог дальше новый.
				state.answered = nil
			end
			state.d_refresh = true
			d_step()
		end
	end)
	state.watch = close
end

M._state = state

local function open()
	if not pane_id() and not state.warned_pane then
		state.warned_pane = true
		vim.notify(
			"claude-input: CLAUDE_INPUT_PANE не задана, трансляции нет",
			vim.log.levels.WARN
		)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_set_current_buf(state.buf)
		vim.cmd("startinsert")
		return
	end
	local buf = vim.api.nvim_create_buf(true, false)
	state.buf = buf
	vim.api.nvim_buf_set_name(buf, BUF_NAME)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].swapfile = false
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].filetype = "markdown"
	wrap_on_show()
	local group = vim.api.nvim_create_augroup("claude_input", { clear = true })
	-- Файл соответствия панелей после `:q` устарел: удаляется, если он указывает на эту панель.
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			local cp, own = pane_id(), vim.env.HERDR_PANE_ID
			if not cp or not own then
				return
			end
			local dir = vim.env.XDG_STATE_HOME
			if not dir or dir == "" then
				dir = vim.fn.expand("~/.local/state")
			end
			local f = dir .. "/claude-input/" .. cp:gsub(":", "_")
			local fh = io.open(f, "r")
			if not fh then
				return
			end
			local content = (fh:read("*a") or ""):gsub("\n$", "")
			fh:close()
			if content == own then
				os.remove(f)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
		group = group,
		buffer = buf,
		callback = function()
			schedule_send()
		end,
	})
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = group,
		buffer = buf,
		callback = function()
			M.submit()
		end,
	})
	-- Shift+Enter и Shift+Пробел отправляют запрос, как `:w`.
	for _, key in ipairs({ "<S-CR>", "<S-Space>" }) do
		vim.keymap.set({ "i", "n" }, key, function()
			M.submit()
		end, { buffer = buf, desc = "claude-input: отправить запрос" })
	end
	-- Содержимое уже повторено в строке ввода Claude Code, поэтому `:q` не требует записи.
	vim.api.nvim_create_autocmd("QuitPre", {
		group = group,
		callback = function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].modified = false
			end
			if state.dbuf and vim.api.nvim_buf_is_valid(state.dbuf) then
				vim.bo[state.dbuf].modified = false
			end
		end,
	})
	local start = vim.api.nvim_get_current_buf()
	vim.api.nvim_set_current_buf(buf)
	-- Пустой безымянный буфер запуска не нужен: без него строка вкладок скрыта.
	if
		start ~= buf
		and vim.api.nvim_buf_get_name(start) == ""
		and vim.bo[start].buftype == ""
		and not vim.bo[start].modified
		and vim.api.nvim_buf_line_count(start) == 1
		and vim.api.nvim_buf_get_lines(start, 0, 1, false)[1] == ""
	then
		pcall(vim.api.nvim_buf_delete, start, {})
	end
	vim.cmd("startinsert")
	M.watch()
end

function M.setup()
	vim.api.nvim_create_user_command("ClaudeInput", open, { desc = "Буфер ввода Claude Code" })
end

return M
