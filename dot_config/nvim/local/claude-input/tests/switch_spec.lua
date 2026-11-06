-- Буфер диалога на поддельном сервере herdr в том же процессе neovim:
-- переключение буферов, цифра, текст свободного ввода, множественный выбор,
-- `:w`, защита по подписи экрана, возврат к буферу ввода.
-- Запуск: nvim --headless --clean -u NONE -l tests/switch_spec.lua
-- Ожидания — до события; зависание ловит предел прогона целиком.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local uv = vim.uv
io.stdout:setvbuf("no")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local sock = dir .. "/herdr.sock"
vim.env.HERDR_SOCKET_PATH = sock
vim.env.CLAUDE_INPUT_PANE = "w1:p1"
vim.env.HERDR_PANE_ID = "w1:p2"
vim.env.XDG_STATE_HOME = dir

local function screen(name)
  local f = assert(io.open(root .. "/tests/fixtures/" .. name .. ".txt"))
  local s = f:read("*a")
  f:close()
  return s
end

local IDLE = "──────\n❯ \n──────\n  -- INSERT -- ⏸ manual mode on\n"
local fake = { status = "idle", screen = IDLE, sent = {}, subs = {}, matchers = {} }

-- Поддельный сервер: строка JSON на запрос, подписки держат соединение.
local server = uv.new_pipe(false)
assert(server:bind(sock))
server:listen(16, function()
  local client = uv.new_pipe(false)
  server:accept(client)
  local acc = ""
  client:read_start(function(err, data)
    if err or not data then
      client:close()
      return
    end
    acc = acc .. data
    local nl = acc:find("\n", 1, true)
    if not nl then
      return
    end
    local req = vim.json.decode(acc:sub(1, nl - 1))
    acc = acc:sub(nl + 1)
    local function reply(result)
      client:write(vim.json.encode({ id = req.id, result = result }) .. "\n")
    end
    if req.method == "pane.get" then
      reply({ pane = { pane_id = req.params.pane_id, agent_status = fake.status } })
    elseif req.method == "pane.read" then
      reply({ read = { text = fake.screen } })
    elseif req.method == "pane.send_text" then
      table.insert(fake.sent, req.params.text)
      reply({ type = "ok" })
    elseif req.method == "pane.send_keys" then
      table.insert(fake.sent, "<" .. table.concat(req.params.keys, " ") .. ">")
      reply({ type = "ok" })
    elseif req.method == "events.subscribe" then
      local sub = req.params.subscriptions[1]
      if sub.type == "pane.output_matched" then
        table.insert(fake.matchers, { client = client, regex = sub.match.value })
      else
        table.insert(fake.subs, client)
      end
      reply({ type = "subscribed" })
    end
  end)
end)

local function push_status(status, scr)
  fake.status = status
  fake.screen = scr
  for _, c in ipairs(fake.subs) do
    if not c:is_closing() then
      c:write(
        vim.json.encode({ event = "pane.agent_status_changed", data = { pane_id = "w1:p1", agent_status = status } })
          .. "\n"
      )
    end
  end
end

-- Перерисовка экрана: подписчики pane.output_matched получают событие
-- (образец в тесте не сверяется: каждый ждёт ровно эту перерисовку).
local function render(scr)
  fake.screen = scr
  local ms = fake.matchers
  fake.matchers = {}
  for _, m in ipairs(ms) do
    if not m.client:is_closing() then
      m.client:write(vim.json.encode({ event = "pane.output_matched", data = { pane_id = "w1:p1" } }) .. "\n")
    end
  end
end

local failed = 0
local function check(name, ok, info)
  if ok then
    io.stdout:write("ok " .. name .. "\n")
  else
    failed = failed + 1
    io.stdout:write("FAIL " .. name .. (info ~= nil and (" — " .. vim.inspect(info)) or "") .. "\n")
  end
end

local FOREVER = 2 ^ 31 - 1
-- Условие проверяется после событий цикла neovim (сокет, vim.schedule), без опроса.
local function wait(cond)
  return vim.wait(FOREVER, cond, FOREVER)
end

local ci = require("claude_input")
local dialog = require("claude_input.dialog")
local st = ci._state
local P = ci.PREFIX
local U, D = dialog.UP, dialog.DOWN

local function cur_name()
  return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(0))
end
local function idle_chain()
  return not st.d_busy and not st.d_edit and not st.d_write and not st.d_refresh
end
-- Правка буфера диалога и ожидание конца цепочки.
local function dialog_set(lines)
  vim.api.nvim_buf_set_lines(st.dbuf, 0, -1, false, lines)
  ci.dialog_changed()
  wait(idle_chain)
end
local function last_sent()
  return fake.sent[#fake.sent]
end
local function dialog_lines()
  return table.concat(vim.api.nvim_buf_get_lines(st.dbuf, 0, -1, false), "\n")
end
-- Экран с выделением на пункте n вместо прежнего.
local function select_row(scr, n)
  scr = scr:gsub("\n❯ (%d+%.)", "\n  %1")
  return (scr:gsub("\n  (" .. n .. "%.)", "\n❯ %1"))
end

ci.setup()
vim.cmd("ClaudeInput")
local input = vim.api.nvim_get_current_buf()
wait(function()
  return #fake.subs == 1 and idle_chain()
end)
check("подписка при открытии", #fake.subs == 1)

-- Черновик в буфере ввода уходит в строку ввода.
vim.api.nvim_buf_set_lines(input, 0, -1, false, { "черновик" })
ci.schedule_send()
wait(function()
  return last_sent() == P .. "черновик"
end)
check("черновик передан", last_sent() == P .. "черновик")

-- :w буфера ввода: текст без `\r`, затем Enter клавишей, буфер очищен.
vim.api.nvim_buf_set_lines(input, 0, -1, false, { "/help" })
vim.cmd("write")
wait(function()
  return last_sent() == "<enter>" and not st.in_flight
end)
check(":w ввода: текст", fake.sent[#fake.sent - 1] == P .. "/help", fake.sent[#fake.sent - 1])
check(":w ввода: Enter клавишей", last_sent() == "<enter>")
check(":w ввода: буфер пуст", table.concat(vim.api.nvim_buf_get_lines(input, 0, -1, false), "") == "")
vim.api.nvim_buf_set_lines(input, 0, -1, false, { "черновик" })
ci.schedule_send()
wait(function()
  return last_sent() == P .. "черновик"
end)

-- Местный /model (idle) буфер диалога не открывает.
push_status("idle", screen("model"))
wait(idle_chain)
check("/model: буфер ввода", cur_name():match("claude://input$") ~= nil, cur_name())

-- 1. Диалог AskUserQuestion: окно переходит на claude://dialog.
local q1 = screen("ask-q1")
push_status("blocked", q1)
wait(function()
  return st.mode == "dialog"
end)
check("blocked: буфер диалога", cur_name():match("claude://dialog$") ~= nil, cur_name())
check("blocked: буфер диалога пуст", dialog_lines() == "")
local n_sent = #fake.sent

-- 2. Цифра 3: две стрелки вниз, без клавиши цифры, буфер очищен.
dialog_set({ "3" })
check("цифра 3: стрелки", last_sent() == D .. D, last_sent())
check("цифра 3: буфер пуст", dialog_lines() == "")

-- 3. Пункта 9 нет: ничего не отправлено, буфер пуст.
fake.screen = select_row(q1, 3)
n_sent = #fake.sent
dialog_set({ "9" })
check("цифра 9: ничего", #fake.sent == n_sent)
check("цифра 9: буфер пуст", dialog_lines() == "")

-- 4. Текст при выделенном пункте ввода уходит в поле.
fake.screen = select_row(q1, 4)
dialog_set({ "свой ответ" })
check("текст в поле", last_sent() == P .. "свой ответ", last_sent())
-- Текст при выделенном другом пункте не отправляется.
fake.screen = select_row(q1, 2)
n_sent = #fake.sent
dialog_set({ "просто текст" })
check("текст не на поле: ничего", #fake.sent == n_sent)
dialog_set({})

-- 5. Передумал: поле с текстом, буфер очищен и сразу набрано 2 одной цепочкой.
local with_text = select_row(q1, 4):gsub("4%. Type something%.", "4. свой ответ")
fake.screen = with_text
st.field_text = "свой ответ"
st.seen_empty = false
vim.api.nvim_buf_set_lines(st.dbuf, 0, -1, false, {})
ci.dialog_changed()
vim.api.nvim_buf_set_lines(st.dbuf, 0, -1, false, { "2" })
ci.dialog_changed()
wait(idle_chain)
check("передумал: очистка поля и стрелки", last_sent() == P .. U .. U, last_sent())
check("передумал: буфер пуст", dialog_lines() == "")

-- 5а. Ctrl+U и цифра одним куском нажатий: одно событие TextChangedI уже с «2»,
-- пустое состояние буфера отмечает on_lines.
-- Экран другой, чем до прежних стрелок: Claude Code их обработал.
fake.screen = select_row(q1, 4):gsub("4%. Type something%.", "4. другой")
st.field_text = "другой"
vim.api.nvim_buf_set_lines(st.dbuf, 0, -1, false, { "другой" })
st.seen_empty = false
vim.api.nvim_set_current_win(vim.fn.win_findbuf(st.dbuf)[1])
local before = #fake.sent
vim.api.nvim_feedkeys(vim.keycode("A<C-u>2<Esc>"), "xt", false)
ci.dialog_changed()
wait(idle_chain)
check("одним куском: одна отправка", #fake.sent == before + 1, #fake.sent - before)
check("одним куском: очистка поля и стрелки", last_sent() == P .. U .. U, last_sent())

-- 6. Защита: экран ещё прежний после стрелок — текст в поле не уходит.
fake.screen = select_row(q1, 4)
dialog_set({ "1" })
check("стрелки к пункту 1", last_sent() == U:rep(3), last_sent())
n_sent = #fake.sent
dialog_set({ "x" })
check("прежний экран: ничего", #fake.sent == n_sent)
fake.screen = select_row(q1, 1)
dialog_set({ "xy" })
check("новый экран, пункт 1: ничего", #fake.sent == n_sent)
dialog_set({})

-- 7. :w в одиночном выборе — Enter.
vim.cmd("write")
wait(idle_chain)
check(":w одиночный: Enter клавишей", last_sent() == "<enter>", last_sent())
check(":w: буфер не изменён", not vim.bo[st.dbuf].modified)
-- Ввод возвращается сразу, пока сервер не сменил экран.
check(
  ":w: сразу буфер ввода",
  cur_name():match("claude://input$") ~= nil and st.mode == "input",
  cur_name()
)
check(
  ":w: прежний текст ввода",
  table.concat(vim.api.nvim_buf_get_lines(input, 0, -1, false), "\n") == "черновик"
)
-- Тот же экран (подпись отвеченного диалога) диалог не открывает.
push_status("blocked", fake.screen)
wait(idle_chain)
check(
  "тот же экран: диалог не открывается",
  st.mode == "input" and cur_name():match("claude://input$") ~= nil
)
check("тот же экран: буфер диалога скрыт", vim.fn.bufwinid(st.dbuf) == -1)
-- Выход из blocked сбрасывает память: такой же диалог дальше новый.
push_status("working", fake.screen)
wait(idle_chain)
push_status("blocked", fake.screen)
wait(function()
  return st.mode == "dialog"
end)
check("после working тот же диалог — новый", cur_name():match("claude://dialog$") ~= nil)

-- 8. Множественный выбор (следующий вопрос — другой экран): диалог открывается заново.
push_status("blocked", screen("ask-q2-multi"))
wait(function()
  return st.mode == "dialog"
end)
check(
  "следующий вопрос: пустой диалог",
  cur_name():match("claude://dialog$") ~= nil and dialog_lines() == ""
)
dialog_set({ "2" })
check("множественный: клавиша 2", last_sent() == "2", last_sent())
vim.cmd("write")
wait(idle_chain)
check(
  ":w множественный: к Submit и Enter",
  fake.sent[#fake.sent - 1] == D:rep(4) and last_sent() == "<enter>",
  { fake.sent[#fake.sent - 1], last_sent() }
)
check(
  ":w множественный: сразу буфер ввода",
  st.mode == "input" and cur_name():match("claude://input$") ~= nil
)

-- 9. Запрос разрешения: цифра 2 — стрелка, подтверждение только по :w.
push_status("working", IDLE)
wait(function()
  return st.mode == "input"
end)
push_status("blocked", screen("perm-bash"))
wait(function()
  return st.mode == "dialog"
end)
local perm_from = #fake.sent
dialog_set({ "2" })
check("разрешение: стрелка вместо цифры", last_sent() == D, last_sent())
for i = perm_from + 1, #fake.sent do
  local t = fake.sent[i]
  if t == "<enter>" then
    check("разрешение: нет Enter без :w", false, t)
  end
end

-- 10. Поле свободного ввода: детектор показывает done, буфер диалога остаётся.
push_status("done", screen("ask-q2-other-text"))
wait(idle_chain)
check(
  "done при поле: буфер диалога",
  st.mode == "dialog" and cur_name():match("claude://dialog$") ~= nil
)

-- 11. Диалог закрыт: буфер ввода с прежним текстом.
push_status("working", IDLE)
wait(function()
  return st.mode == "input"
end)
check("возврат: буфер ввода", cur_name():match("claude://input$") ~= nil, cur_name())
check(
  "возврат: прежний текст",
  table.concat(vim.api.nvim_buf_get_lines(input, 0, -1, false), "\n") == "черновик"
)

-- 12. Экран доверия: цифра 2 — стрелка, :w — Enter.
push_status("blocked", screen("trust"))
wait(function()
  return st.mode == "dialog"
end)
dialog_set({ "2" })
check("доверие: стрелка", last_sent() == D, last_sent())
vim.cmd("write")
wait(idle_chain)
check("доверие: :w — Enter", last_sent() == "<enter>", last_sent())

-- 13. Прежний экран после стрелок: :w и цифра ждут перерисовки (pane.output_matched).
push_status("working", IDLE)
wait(function()
  return st.mode == "input"
end)
local multi = screen("ask-q2-multi")
push_status("blocked", multi)
wait(function()
  return st.mode == "dialog"
end)
dialog_set({ "4" })
check("к полю: стрелки", last_sent() == D:rep(3), last_sent())
n_sent = #fake.sent
vim.cmd("write")
wait(idle_chain)
check(":w на прежнем экране отложен", #fake.sent == n_sent)
local function open_matchers()
  local n = 0
  for _, m in ipairs(fake.matchers) do
    if not m.client:is_closing() then
      n = n + 1
    end
  end
  return n
end
wait(function()
  return open_matchers() == 1
end)
check("ожидание выделения", open_matchers() == 1, open_matchers())
render((multi:gsub("\n❯ 1%.", "\n  1."):gsub("\n  4%. %[ %]", "\n❯ 4. [ ]")))
wait(function()
  return last_sent() == "<enter>" and idle_chain()
end)
check(":w после перерисовки: к Submit", fake.sent[#fake.sent - 1] == D, fake.sent[#fake.sent - 1])
check(":w после перерисовки: буфер ввода", st.mode == "input")
push_status("working", IDLE)
wait(idle_chain)
push_status("blocked", multi)
wait(function()
  return st.mode == "dialog"
end)
-- Цифра на прежнем экране не теряется.
render(multi)
st.guard = nil
dialog_set({ "4" })
dialog_set({ "1" })
check("цифра на прежнем экране отложена", last_sent() == D:rep(3), last_sent())
wait(function()
  return open_matchers() == 1
end)
render((multi:gsub("\n❯ 1%.", "\n  1."):gsub("\n  4%. %[ %]", "\n❯ 4. [ ]")))
wait(function()
  return last_sent() == U:rep(3) .. "1" and idle_chain()
end)
check("цифра после перерисовки", last_sent() == U:rep(3) .. "1", last_sent())
-- Отметки подряд без перерисовки: защита не ставится.
render(multi)
st.guard = nil
dialog_set({ "2" })
dialog_set({ "3" })
check(
  "отметки подряд",
  fake.sent[#fake.sent - 1] == "2" and last_sent() == "3",
  { fake.sent[#fake.sent - 1], last_sent() }
)

-- 14. Статус idle, а кадр ещё диалога без выделенного поля — возврат к буферу ввода.
push_status("idle", multi)
wait(function()
  return st.mode == "input"
end)
check(
  "idle с прежним кадром: буфер ввода",
  cur_name():match("claude://input$") ~= nil,
  cur_name()
)

-- 15. Визуальный перенос: на окне буферов модуля, соседний буфер не затронут,
-- в herdr длинная строка уходит одной строкой без переносов.
local function wrap_on(win)
  return vim.wo[win].wrap and vim.wo[win].linebreak and vim.wo[win].breakindent
end
local other = vim.api.nvim_create_buf(false, true)
vim.cmd("vsplit")
local other_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(other_win, other)
vim.wo[other_win].wrap = false
vim.wo[other_win].linebreak = false
vim.wo[other_win].breakindent = false
check("перенос: окно буфера ввода", wrap_on(vim.fn.win_findbuf(input)[1]))
check(
  "перенос: соседнее окно не затронуто",
  not wrap_on(other_win) and not vim.wo[other_win].wrap
)
vim.api.nvim_win_set_buf(other_win, st.dbuf)
check("перенос: окно буфера диалога", wrap_on(other_win))
vim.api.nvim_win_set_buf(other_win, other)
check(
  "перенос: после ухода диалога окно как было",
  not wrap_on(other_win) and not vim.wo[other_win].wrap
)
-- Уход буфера из нетекущего окна возвращает опции этого окна.
local w_in = vim.fn.win_findbuf(input)[1]
vim.api.nvim_set_current_win(other_win)
vim.api.nvim_win_set_buf(w_in, other)
check(
  "перенос: уход из нетекущего окна",
  not vim.wo[w_in].linebreak and not vim.wo[w_in].breakindent
)
vim.api.nvim_win_set_buf(w_in, input)
check("перенос: возврат буфера ввода в окно", wrap_on(w_in))
vim.cmd("close")
local long = ("слово "):rep(40)
local n_before = #fake.sent
vim.api.nvim_buf_set_lines(input, 0, -1, false, { long })
ci.schedule_send()
wait(function()
  return #fake.sent > n_before and idle_chain()
end)
check(
  "перенос: в буфере одна строка",
  vim.api.nvim_buf_line_count(input) == 1 and vim.api.nvim_buf_get_lines(input, 0, 1, false)[1] == long
)
check(
  "перенос: в herdr без переносов",
  not last_sent():find("\n", 1, true) and last_sent():find(long, 1, true) ~= nil,
  last_sent()
)

-- Esc уходит только в префиксе очистки поля.
for _, t in ipairs(fake.sent) do
  local rest = t:gsub(vim.pesc(P), "")
  if rest:find("\27[^%[]") or rest:find("\27%[27u", 1) then
    check("Esc только в префиксе", false, t)
  end
end

io.stdout:write(failed == 0 and "ALL OK\n" or ("FAILED " .. failed .. "\n"))
vim.cmd(failed == 0 and "qa!" or "cq!")
