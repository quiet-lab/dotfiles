-- Разбор экрана диалога Claude Code и клавиши ответа (design.md изменения
-- claude-dialog-buffer, решения E1, E3, E5). Чистые функции без обращения к сокету.
local M = {}

M.UP = "\27[A"
M.DOWN = "\27[B"
M.ENTER = "\r"

local SEL = "❯"
local FREE_PLACEHOLDER = { ["Type something."] = true, ["Type something"] = true }

-- Подвал диалога: подсказка Enter или Esc to cancel.
local function footer_kind(line)
	local l = line:lower()
	local enter = l:find("enter to select", 1, true) or l:find("enter to confirm", 1, true)
	local esc = l:find("esc to cancel", 1, true)
	if enter or esc then
		return { enter = enter ~= nil }
	end
end

-- Строка без ведущих пробелов и признак выделения `❯` перед ней.
local function split_sel(line)
	local indent, rest = line:match("^(%s*)(.*)$")
	local selected = false
	if rest:sub(1, #SEL) == SEL then
		selected = true
		rest = rest:sub(#SEL + 1)
	end
	local gap, body = rest:match("^(%s*)(.*)$")
	return #indent, selected, body, #gap
end

-- Нумерованный пункт: перед номером только пробелы и `❯`.
local function numbered(line)
	local indent, selected, body = split_sel(line)
	if indent > 6 then
		return nil
	end
	local n, label = body:match("^(%d+)%.%s+(.-)%s*$")
	if n then
		return tonumber(n), label, selected
	end
end

local function checkbox(label)
	return label:match("^%[ %]") or label:match("^%[✔%]") or label:match("^%[[xX]%]")
end

local function strip_checkbox(label)
	local rest = label:match("^%[[^%]]*%]%s*(.*)$")
	return rest or label
end

-- Нумерованные пункты снизу вверх: номера подряд по убыванию до 1.
local function numbered_rows(lines, last)
	local rows = {}
	local expect
	local submit
	for i = last, 1, -1 do
		local n, label, selected = numbered(lines[i])
		if n then
			if expect and n ~= expect then
				return nil
			end
			table.insert(rows, 1, { num = n, label = label, selected = selected, line = i })
			if n == 1 then
				if submit then
					table.insert(rows, submit.pos(rows), submit.row)
				end
				return rows
			end
			expect = n - 1
		elseif expect then
			local _, selected2, body = split_sel(lines[i])
			if body == "Submit" and not submit then
				local row = { label = "Submit", selected = selected2, submit = true, line = i }
				submit = {
					row = row,
					pos = function(rs)
						for k, r in ipairs(rs) do
							if r.line > row.line then
								return k
							end
						end
						return #rs + 1
					end,
				}
			end
		end
	end
	return nil
end

-- Пункты без номеров (экран доверия): подряд идущие строки с отступом строки `❯`.
local function plain_rows(lines, last)
	local at
	for i = last, 1, -1 do
		local _, selected = split_sel(lines[i])
		if selected then
			at = i
			break
		end
	end
	if not at then
		return nil
	end
	local indent, _, _, gap = split_sel(lines[at])
	local col = indent + 1 + gap
	local function is_row(i)
		local l = lines[i]
		if not l or i > last then
			return false
		end
		local lead = l:match("^(%s*)")
		return #lead == col and #l > col
	end
	local first, final = at, at
	while is_row(first - 1) do
		first = first - 1
	end
	while is_row(final + 1) do
		final = final + 1
	end
	local rows = {}
	for i = first, final do
		local _, selected, body = split_sel(lines[i])
		local label = body:gsub("%s+$", "")
		table.insert(rows, { num = #rows + 1, label = label, selected = selected, line = i, plain = true })
	end
	return rows
end

-- Разбор экрана: nil, если это не диалог с пунктами выбора.
-- Поля: rows (пункты сверху вниз, строка Submit — без num), sel (индекс выделенного),
-- multi, free (номер пункта свободного ввода), free_text, review.
function M.parse(text)
	local lines = {}
	for l in (text .. "\n"):gmatch("(.-)\r?\n") do
		table.insert(lines, (l:gsub("%s+$", "")))
	end
	local f = #lines
	while f > 0 and lines[f] == "" do
		f = f - 1
	end
	if f == 0 then
		return nil
	end
	local foot = footer_kind(lines[f])
	local rows
	if foot then
		rows = numbered_rows(lines, f - 1)
	else
		-- Вкладка обзора ответов AskUserQuestion выводится без подвала.
		rows = numbered_rows(lines, f)
		if not rows or rows[1].label ~= "Submit answers" then
			return nil
		end
		foot = { enter = false }
	end
	local numbered_ok = false
	if rows then
		for _, r in ipairs(rows) do
			if r.selected then
				numbered_ok = true
			end
		end
	end
	if not numbered_ok then
		rows = foot.enter and plain_rows(lines, f - 1) or nil
	end
	if not rows or #rows == 0 then
		return nil
	end
	local d = { rows = rows, multi = false, review = false, free_text = "" }
	local chat
	for k, r in ipairs(rows) do
		if r.selected then
			d.sel = k
		end
		if r.num and checkbox(r.label) then
			d.multi = true
		end
		if r.label == "Chat about this" then
			chat = r.num
		end
		if r.label == "Submit answers" then
			d.review = true
		end
	end
	if not d.sel then
		return nil
	end
	if chat and chat > 1 then
		d.free = chat - 1
		local fr = rows[M.index(d, d.free)]
		local t = strip_checkbox(fr.label)
		d.free_text = FREE_PLACEHOLDER[t] and "" or t
	end
	if not d.multi then
		-- Строка Submit — позиция выделения только в множественном выборе.
		local kept = {}
		for _, r in ipairs(rows) do
			if not r.submit or r.selected then
				table.insert(kept, r)
			end
		end
		d.rows = kept
		for k, r in ipairs(kept) do
			if r.selected then
				d.sel = k
			end
		end
	end
	return d
end

-- Индекс пункта с номером n в d.rows.
function M.index(d, n)
	for k, r in ipairs(d.rows) do
		if r.num == n then
			return k
		end
	end
end

-- Подпись диалога: пункты, отметки, выделение. Меняется после стрелок, Enter
-- и правки поля; совпадение с подписью до отправки — экран ещё прежний.
function M.signature(d)
	local parts = {}
	for _, r in ipairs(d.rows) do
		table.insert(parts, (r.selected and ">" or " ") .. (r.num or "S") .. " " .. r.label)
	end
	return table.concat(parts, "\n")
end

-- Выделен пункт свободного ввода.
function M.on_free(d)
	return d.free ~= nil and d.rows[d.sel].num == d.free
end

-- Образец (регулярное выражение Rust для pane.output_matched) строки пункта row,
-- когда он выделен; nil — образца нет (пункт без номера).
function M.selected_regex(row)
	if row.submit then
		return "(?m)^\\s*❯\\s+Submit\\s*$"
	end
	if row.num and not row.plain then
		return "(?m)^\\s*❯\\s*" .. row.num .. "\\.\\s"
	end
end

local function arrows(from, to)
	if to > from then
		return M.DOWN:rep(to - from)
	end
	return M.UP:rep(from - to)
end

-- Клавиши для числа n (E3): nil — пункта нет. prefix — очистка поля
-- (передаётся, только если выделено поле и в нём есть текст).
function M.digit_keys(d, n, prefix)
	local t = M.index(d, n)
	if not t then
		return nil
	end
	prefix = prefix or ""
	if d.multi and not d.review and n ~= d.free and checkbox(d.rows[t].label) then
		if M.on_free(d) then
			return prefix .. arrows(d.sel, t) .. tostring(n)
		end
		return tostring(n)
	end
	return prefix .. arrows(d.sel, t)
end

-- Клавиши подтверждения (E5).
function M.submit_keys(d)
	if d.multi and not d.review then
		for k, r in ipairs(d.rows) do
			if r.submit then
				return arrows(d.sel, k) .. M.ENTER
			end
		end
	end
	return M.ENTER
end

return M
