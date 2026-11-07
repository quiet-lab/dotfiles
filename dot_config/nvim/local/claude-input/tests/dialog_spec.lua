-- Разбор снятых экранов диалогов Claude Code 2.1.319 и клавиши ответа.
-- Запуск из корня плагина: nvim --headless --clean -u NONE --cmd 'set rtp+=.' -l tests/dialog_spec.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local dialog = require("claude_input.dialog")

local failed = 0
local function check(name, ok, info)
  if ok then
    io.stdout:write("ok " .. name .. "\n")
  else
    failed = failed + 1
    io.stdout:write("FAIL " .. name .. (info and (" — " .. vim.inspect(info)) or "") .. "\n")
  end
end

local function screen(name)
  local f = assert(io.open(root .. "/tests/fixtures/" .. name .. ".txt"))
  local s = f:read("*a")
  f:close()
  return s
end

local function nums(d)
  local out = {}
  for _, r in ipairs(d.rows) do
    table.insert(out, r.num or "S")
  end
  return table.concat(out, ",")
end

local PREFIX = "<P>"
local U, D = dialog.UP, dialog.DOWN

-- Экран доверия: пункты без номеров, выделен «No, exit».
local d = dialog.parse(screen("trust"))
check("trust: диалог", d ~= nil)
check("trust: два пункта", d and nums(d) == "1,2", d and nums(d))
check("trust: выделен 1", d and d.sel == 1 and d.rows[1].label == "No, exit")
check("trust: без свободного ввода", d and d.free == nil and not d.multi)
check("trust: 2 — стрелка вниз", d and dialog.digit_keys(d, 2) == D)
check("trust: 3 — пункта нет", d and dialog.digit_keys(d, 3) == nil)
check("trust: :w — Enter", d and dialog.submit_keys(d) == "\r")

-- AskUserQuestion, одиночный выбор.
d = dialog.parse(screen("ask-q1"))
check("ask-q1: диалог", d ~= nil)
check("ask-q1: пункты 1–5", d and nums(d) == "1,2,3,4,5", d and nums(d))
check("ask-q1: выделен 1", d and d.sel == 1)
check("ask-q1: свободный ввод 4, пусто", d and d.free == 4 and d.free_text == "")
check("ask-q1: не множественный", d and not d.multi and not d.review)
check("ask-q1: 3 — две стрелки вниз, без цифры", d and dialog.digit_keys(d, 3) == D .. D)
check("ask-q1: 5 — Chat about this", d and dialog.digit_keys(d, 5) == D:rep(4))
check("ask-q1: 1 — ничего", d and dialog.digit_keys(d, 1) == "")
check("ask-q1: 9 — пункта нет", d and dialog.digit_keys(d, 9) == nil)
check("ask-q1: :w — Enter", d and dialog.submit_keys(d) == "\r")

-- AskUserQuestion из одного вопроса (без вкладки Submit).
d = dialog.parse(screen("ask-single"))
check("single: пункты 1–5", d and nums(d) == "1,2,3,4,5", d and nums(d))
check("single: свободный ввод 4", d and d.free == 4 and not d.multi)
check("single: 3 — две стрелки", d and dialog.digit_keys(d, 3) == D .. D)

-- Множественный выбор: строка Submit — позиция выделения.
d = dialog.parse(screen("ask-q2-multi"))
check("multi: диалог", d ~= nil)
check("multi: позиции 1–4, Submit, 5", d and nums(d) == "1,2,3,4,S,5", d and nums(d))
check("multi: множественный", d and d.multi)
check("multi: свободный ввод 4", d and d.free == 4 and d.free_text == "")
check("multi: 2 — клавиша 2", d and dialog.digit_keys(d, 2) == "2")
check("multi: 4 — стрелки к полю", d and dialog.digit_keys(d, 4) == D:rep(3))
check("multi: 5 — через Submit", d and dialog.digit_keys(d, 5) == D:rep(5))
check("multi: :w — стрелки к Submit и Enter", d and dialog.submit_keys(d) == D:rep(4) .. "\r")

-- Множественный выбор, выделено поле с текстом.
d = dialog.parse(screen("ask-q2-other-text"))
check("other: диалог при подвале с INSERT", d ~= nil)
check("other: выделено поле", d and dialog.on_free(d))
check("other: текст поля", d and d.free_text == "абв где", d and d.free_text)
check(
  "other: 2 — очистка, стрелки, клавиша",
  d and dialog.digit_keys(d, 2, PREFIX) == PREFIX .. U .. U .. "2"
)
check("other: 1 без очистки", d and dialog.digit_keys(d, 1) == U:rep(3) .. "1")
check("other: :w — стрелка к Submit", d and dialog.submit_keys(d) == D .. "\r")

-- Выделен Chat about this.
d = dialog.parse(screen("ask-q2-chat-selected"))
check("chat: выделен 5", d and d.rows[d.sel].num == 5, d and d.sel)
check("chat: :w — вверх к Submit", d and dialog.submit_keys(d) == U .. "\r")

-- Вкладка обзора ответов.
d = dialog.parse(screen("ask-review"))
check("review: диалог", d ~= nil)
check("review: два пункта, обзор", d and nums(d) == "1,2" and d.review)
check("review: 2 — стрелка", d and dialog.digit_keys(d, 2) == D)
check("review: :w — Enter", d and dialog.submit_keys(d) == "\r")

-- Сессия с именем: под подвалом и под обзором линия рамки «──── имя ─».
d = dialog.parse(screen("ask-q2-named"))
check("named: диалог", d ~= nil)
check("named: пункты 1–4", d and nums(d) == "1,2,3,4", d and nums(d))
check("named: выделен 1, свободный ввод 3", d and d.sel == 1 and d.free == 3)
check("named: 2 — стрелка вниз", d and dialog.digit_keys(d, 2) == D)
d = dialog.parse(screen("ask-q2-named-free"))
check("named-free: выделено поле с текстом", d and dialog.on_free(d) and d.free_text == "1", d and d.free_text)
d = dialog.parse(screen("ask-review-named"))
check("review-named: диалог обзора", d ~= nil and d.review and nums(d) == "1,2", d and nums(d))
check("review-named: :w — Enter", d and dialog.submit_keys(d) == "\r")

-- Разрешение Bash и Write.
d = dialog.parse(screen("perm-bash"))
check("perm-bash: пункты 1,2", d and nums(d) == "1,2" and d.sel == 1, d and nums(d))
check("perm-bash: 2 — стрелка, не цифра", d and dialog.digit_keys(d, 2) == D)
check("perm-bash: без свободного ввода", d and d.free == nil)
d = dialog.parse(screen("perm-write"))
check("perm-write: пункты 1–3", d and nums(d) == "1,2,3", d and nums(d))
check("perm-write: 3 — две стрелки", d and dialog.digit_keys(d, 3) == D .. D)

-- Местный /model разбирается (статус idle отсекает его выше по цепочке).
d = dialog.parse(screen("model"))
check("model: выделен 4", d and d.rows[d.sel].num == 4)

-- Не диалоги.
check(
  "строка ввода — не диалог",
  dialog.parse("──────\n❯ текст\n──────\n  -- INSERT -- ⏸ manual mode on\n") == nil
)
check(
  "MCP elicitation — не диалог",
  dialog.parse('MCP server "x" requests your input\n ❯ Accept\n   Decline\n Esc to cancel\n') == nil
)
check(
  "нумерованный вывод выше без выделения — не диалог",
  dialog.parse("  1. раз\n  2. два\n❯ текст\n Esc to cancel\n") == nil
)
check(
  "пропуск номера — не диалог",
  dialog.parse(" ❯ 1. Yes\n   3. No\n Esc to cancel\n") == nil
)
check("пустой экран", dialog.parse("") == nil)

io.stdout:write(failed == 0 and "ALL OK\n" or ("FAILED " .. failed .. "\n"))
vim.cmd(failed == 0 and "qa!" or "cq!")
