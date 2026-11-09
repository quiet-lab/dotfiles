-- Буфер диалога на поддельном сервере herdr в том же процессе neovim:
-- переключение буферов, цифра, текст свободного ввода, множественный выбор,
-- `:w`, защита по подписи экрана, возврат к буферу ввода.
-- Запуск: nvim --headless --clean -u NONE -l tests/switch_spec.lua
-- Ожидания — до события; зависание ловит предел прогона целиком.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local dialog_mod = require("claude_input.dialog")
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
local fake = { cwd = "/proj/a", status = "idle", screen = IDLE, sent = {}, subs = {}, matchers = {} }

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
      reply({ pane = { pane_id = req.params.pane_id, agent_status = fake.status, cwd = fake.cwd } })
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
        reply({ type = "subscribed" })
        -- Как herdr: образец, уже совпадающий с экраном, срабатывает сразу.
        if fake.fires and fake.fires(sub.match.value, fake.screen) then
          client:write(vim.json.encode({ event = "pane.output_matched", data = { pane_id = "w1:p1" } }) .. "\n")
        else
          table.insert(fake.matchers, { client = client, regex = sub.match.value })
        end
        return
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
      c:write(vim.json.encode({
        event = "pane.agent_status_changed",
        data = { pane_id = "w1:p1", agent_status = status },
      }) .. "\n")
    end
  end
end

-- Перерисовка экрана: подписчики pane.output_matched получают событие
-- (образец в тесте не сверяется: каждый ждёт ровно эту перерисовку).
-- Образец строки вкладок карточки (card_regex) срабатывает, только когда
-- в строке вкладок экрана отвечено не меньше вопросов, чем он ждёт.
local function card_fires(regex, scr)
  local need = regex:match("^%^\\s%*←.-{(%d+)}$")
  if not need then
    return nil
  end
  for l in (scr .. "\n"):gmatch("(.-)\n") do
    if l:match("^%s*←.*→%s*$") then
      local _, n = l:gsub("☒", "")
      return n >= tonumber(need)
    end
  end
  return false
end

-- Образец строки ввода (PROMPT_REGEX) срабатывает на экране строки ввода.
local function prompt_fires(regex, scr)
  if regex ~= dialog_mod.PROMPT_REGEX then
    return nil
  end
  return scr:find("-- INSERT -- ⏸", 1, true) ~= nil or scr:find("⏵⏵", 1, true) ~= nil
end

fake.fires = function(regex, scr)
  local card = card_fires(regex, scr)
  if card == nil then
    card = prompt_fires(regex, scr)
  end
  return card == true
end

local function render(scr)
  fake.screen = scr
  local ms = fake.matchers
  fake.matchers = {}
  for _, m in ipairs(ms) do
    local card = card_fires(m.regex, scr)
    if card == nil then
      card = prompt_fires(m.regex, scr)
    end
    if card == false then
      table.insert(fake.matchers, m)
    elseif not m.client:is_closing() then
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

-- 7. :w на вопросе карточки из нескольких вопросов — Enter; буфер диалога
-- остаётся открытым до конца карточки.
vim.cmd("write")
wait(idle_chain)
check(":w карточки: Enter клавишей", last_sent() == "<enter>", last_sent())
check(":w: буфер не изменён", not vim.bo[st.dbuf].modified)
check(
  ":w карточки: диалог остаётся, буфер пуст",
  st.mode == "dialog" and cur_name():match("claude://dialog$") ~= nil and dialog_lines() == "",
  cur_name()
)

-- 8. Переход к следующему вопросу (строка вкладок) приходит событием
-- pane.output_matched при неизменном статусе blocked.
render(screen("ask-q2-multi"))
wait(function()
  return st.guard == nil and idle_chain()
end)
check(
  "следующий вопрос: тот же пустой диалог",
  st.mode == "dialog" and cur_name():match("claude://dialog$") ~= nil and dialog_lines() == ""
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
check(":w множественный: диалог остаётся", st.mode == "dialog")
-- Множественный выбор не на последнем вопросе: кнопка Next (до этого — переход карточки).
render(screen("ask-review"))
wait(function()
  return st.guard == nil and idle_chain()
end)
render(screen("ask-q1-multi-next"))
wait(function()
  return st.guard == nil and idle_chain()
end)
vim.cmd("write")
wait(idle_chain)
check(
  ":w кнопка Next: стрелки и Enter",
  fake.sent[#fake.sent - 1] == D:rep(4) and last_sent() == "<enter>",
  { fake.sent[#fake.sent - 1], last_sent() }
)
render(screen("ask-review"))
wait(function()
  return st.guard == nil and idle_chain()
end)
check("обзор: диалог остаётся", st.mode == "dialog" and ci._watches.card == nil)
vim.cmd("write")
wait(idle_chain)
check(":w обзор: Enter", last_sent() == "<enter>", last_sent())
-- Ввод возвращается сразу, пока сервер не сменил экран.
check(
  ":w обзор: сразу буфер ввода",
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
check("тот же экран: буфер диалога удалён", st.dbuf == nil)
-- Выход из blocked сбрасывает память: такой же диалог дальше новый.
push_status("working", fake.screen)
wait(idle_chain)
push_status("blocked", fake.screen)
wait(function()
  return st.mode == "dialog"
end)
check("после working тот же диалог — новый", cur_name():match("claude://dialog$") ~= nil)

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
    if not m.client:is_closing() and card_fires(m.regex, "") == nil and prompt_fires(m.regex, "") == nil then
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
check(
  ":w после перерисовки: вопрос карточки — диалог остаётся",
  st.mode == "dialog"
)
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

-- 14. Статус idle при кадре карточки: herdr держит idle после правки поля,
-- буфер диалога остаётся; строка ввода на экране закрывает и удаляет его.
push_status("idle", multi)
wait(idle_chain)
check("idle с кадром карточки: диалог остаётся", st.mode == "dialog", st.mode)
render(IDLE)
wait(function()
  return st.mode == "input"
end)
check(
  "строка ввода: буфер ввода, буфер диалога удалён",
  cur_name():match("claude://input$") ~= nil and st.dbuf == nil,
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
-- Буфер диалога существует только во время диалога.
push_status("blocked", screen("trust"))
wait(function()
  return st.mode == "dialog" and idle_chain()
end)
vim.api.nvim_win_set_buf(other_win, st.dbuf)
check("перенос: окно буфера диалога", wrap_on(other_win))
vim.api.nvim_win_set_buf(other_win, other)
check(
  "перенос: после ухода диалога окно как было",
  not wrap_on(other_win) and not vim.wo[other_win].wrap
)
push_status("working", IDLE)
wait(function()
  return st.mode == "input" and idle_chain()
end)
check("перенос: буфер диалога удалён после диалога", st.dbuf == nil)
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

-- 14. Shift+Enter и Shift+Пробел — то же, что :w, в буфере диалога и в буфере ввода.
for _, key in ipairs({ "<S-CR>", "<S-Space>" }) do
  push_status("working", IDLE)
  wait(function()
    return st.mode == "input"
  end)
  local ibuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, { "запрос" })
  vim.api.nvim_feedkeys(vim.keycode("A" .. key .. "<Esc>"), "xt", false)
  wait(function()
    return not st.in_flight and idle_chain()
  end)
  local text = table.concat(vim.api.nvim_buf_get_lines(ibuf, 0, -1, false), "\n")
  check(key .. " в буфере ввода: буфер очищен", text == "", text)
  check(
    key .. " в буфере ввода: запрос и Enter",
    fake.sent[#fake.sent - 1] == P .. "запрос" and last_sent() == "<enter>",
    { fake.sent[#fake.sent - 1], last_sent() }
  )
  vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, { "" })
  push_status("blocked", screen("trust"))
  wait(function()
    return st.mode == "dialog"
  end)
  dialog_set({ "2" })
  check(key .. ": стрелка по цифре", last_sent() == D, last_sent())
  vim.api.nvim_feedkeys(vim.keycode("i" .. key), "xt", false)
  wait(idle_chain)
  check(key .. " в режиме вставки: Enter", last_sent() == "<enter>", last_sent())
  check(
    key .. ": окно возвращено к вводу",
    st.mode == "input" and cur_name():match("claude://input$") ~= nil
  )

  -- Обычный режим.
  push_status("working", IDLE)
  wait(function()
    return st.mode == "input"
  end)
  push_status("blocked", screen("trust"))
  wait(function()
    return st.mode == "dialog"
  end)
  dialog_set({ "2" })
  vim.api.nvim_feedkeys(vim.keycode("<Esc>" .. key), "xt", false)
  wait(idle_chain)
  check(key .. " в обычном режиме: Enter", last_sent() == "<enter>", last_sent())
  check(key .. " в обычном режиме: окно возвращено к вводу", st.mode == "input")

  -- Цифра и подтверждение одним пакетом ввода.
  push_status("working", IDLE)
  wait(function()
    return st.mode == "input"
  end)
  push_status("blocked", screen("trust"))
  wait(function()
    return st.mode == "dialog"
  end)
  local nb = #fake.sent
  vim.api.nvim_feedkeys(vim.keycode("i2" .. key), "xt", false)
  wait(idle_chain)
  check(
    key .. " одним пакетом: стрелки, затем Enter",
    fake.sent[nb + 1] == D and last_sent() == "<enter>",
    table.concat(fake.sent, "|", nb + 1)
  )
end

-- Esc уходит только в префиксе очистки поля.
for _, t in ipairs(fake.sent) do
  local rest = t:gsub(vim.pesc(P), "")
  if rest:find("\27[^%[]") or rest:find("\27%[27u", 1) then
    check("Esc только в префиксе", false, t)
  end
end

-- 16. Подсказка, обзор в idle и отмена по Ctrl+C.
push_status("working", IDLE)
wait(function()
  return st.mode == "input" and idle_chain()
end)
push_status("blocked", screen("ask-review"))
wait(function()
  return st.mode == "dialog" and idle_chain()
end)
local hns = vim.api.nvim_create_namespace("claude_input_hint")
local hwin = ci._hint_win()
local hbuf = ci._hint_buf()
local hl = hbuf and vim.api.nvim_buf_get_lines(hbuf, 0, -1, false)
local hcfg0 = hwin and vim.api.nvim_win_get_config(hwin)
local htitle = hwin and vim.wo[hwin].winbar
check(
  "подсказка: заголовок, пункты и клавиши в строках «клавиша → описание»",
  hl
    and htitle:find("Обзор ответов", 1, true)
    and #hl == 5
    and hl[1]:find("1 → ❯ Submit answers", 1, true)
    and hl[#hl]:find("C-c → отменить диалог", 1, true),
  { htitle, hl }
)
check(
  "подсказка: в буфере диалога нет extmark'ов",
  #vim.api.nvim_buf_get_extmarks(st.dbuf, hns, 0, -1, {}) == 0
)
local hc = hwin and vim.api.nvim_win_get_config(hwin)
local dwin = vim.fn.win_findbuf(st.dbuf)[1]
local function hint_geometry_ok()
  local dw, hw = vim.api.nvim_win_get_width(dwin), vim.api.nvim_win_get_width(hwin)
  local total = dw + hw + 1
  return hw == math.max(20, math.floor(total / 5)) and total == vim.o.columns
end
local dpos, hpos = vim.api.nvim_win_get_position(dwin), vim.api.nvim_win_get_position(hwin)
check(
  "подсказка: окно разделения справа от окна диалога, не плавающее",
  hc
    and hc.relative == ""
    and hpos[2] > dpos[2]
    and hpos[1] == dpos[1]
    and hpos[2] == dpos[2] + vim.api.nvim_win_get_width(dwin) + 1,
  { hc, dpos, hpos }
)
-- Окно neovim без интерфейса не перекладывает окна при смене `columns`,
-- поэтому широкая панель проверяется самой функцией ширины, а реальное окно —
-- на нынешней панели (80 столбцов: пятая часть меньше 20, подсказке 20).
check(
  "подсказка: узкая панель — 20 столбцов",
  vim.api.nvim_win_get_width(hwin) == 20 and hint_geometry_ok()
)
check(
  "подсказка: ширина — пятая часть, не меньше 20",
  ci._hint_width(60) == 20
    and ci._hint_width(100) == 20
    and ci._hint_width(101) == 20
    and ci._hint_width(160) == 32
    and ci._hint_width(200) == 40
)
check("подсказка: фокус в окне диалога", vim.api.nvim_get_current_win() == dwin)
-- herdr держит idle после правки поля: цифра на обзоре переводит выделение.
st.status = "idle"
dialog_set({ "2" })
check("обзор в idle: стрелка к Cancel", last_sent() == D and st.mode == "dialog", last_sent())
render((screen("ask-review"):gsub("❯ 1%.", "  1."):gsub("  2%. Cancel", "❯ 2. Cancel")))
wait(idle_chain)
vim.api.nvim_feedkeys(vim.keycode("i<C-c>"), "xt", false)
wait(idle_chain)
check("Ctrl+C: Esc в Claude Code", last_sent() == "<esc>", last_sent())
check(
  "Ctrl+C: буфер ввода, буфер диалога удалён",
  st.mode == "input" and cur_name():match("claude://input$") ~= nil and st.dbuf == nil
)
check(
  "Ctrl+C: окно подсказки закрыто",
  ci._hint_win() == nil and not vim.api.nvim_win_is_valid(hwin)
)

-- История ввода: файл с записями двух проектов, дублями и многострочной записью.
local hist_path = dir .. "/history.jsonl"
do
  local rows = {
    { "one", "/proj/a" },
    { "other", "/proj/b" },
    { "two", "/proj/a" },
    { "two", "/proj/a" },
    { "x", "/proj/b" },
    { "три\nстроки [Pasted text #1 +2 lines]", "/proj/a" },
  }
  local out = {}
  for _, r in ipairs(rows) do
    table.insert(out, vim.json.encode({ display = r[1], project = r[2], sessionId = "s", timestamp = 1 }))
  end
  vim.fn.writefile(out, hist_path)
end
ci.HISTORY_PATH = hist_path
local function buf_text()
  return table.concat(vim.api.nvim_buf_get_lines(input, 0, -1, false), "\n")
end
-- Нажатие стрелки и ожидание конца отправки.
local function arrow(key)
  local n = #fake.sent
  vim.api.nvim_feedkeys(vim.keycode(key), "xt", false)
  return n
end
local function settle(n)
  wait(function()
    return #fake.sent > n and idle_chain() and not st.in_flight
  end)
end
-- Круг запрос-ответ по сокету: события, посланные раньше, обработаны (без срока).
local function sync()
  local done
  ci._get_status("w1:p1", function()
    done = true
  end)
  wait(function()
    return done
  end)
  vim.wait(0)
end
local function set_input(lines)
  vim.api.nvim_buf_set_lines(input, 0, -1, false, lines)
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = input })
  wait(function()
    return not st.in_flight
  end)
end

push_status("idle", IDLE)
wait(function()
  return not st.waiting and idle_chain() and not st.in_flight
end)
set_input({})
vim.cmd("startinsert")
local n = arrow("<Up>")
settle(n)
check(
  "история: <Up> на пустом буфере — последняя запись проекта",
  buf_text() == "три\nстроки [Pasted text #1 +2 lines]",
  buf_text()
)
check(
  "история: запись ушла в панель одним pane.send_text",
  last_sent() == P .. "три\nстроки [Pasted text #1 +2 lines]",
  last_sent()
)
check(
  "история: курсор в конце последней строки",
  vim.api.nvim_win_get_cursor(0)[1] == 2
)
-- Курсор на второй строке: <Up> двигает курсор, не листает.
local before = #fake.sent
vim.api.nvim_feedkeys(vim.keycode("<Up>"), "xt", false)
check(
  "история: <Up> в середине текста двигает курсор",
  vim.api.nvim_win_get_cursor(0)[1] == 1 and buf_text():find("три", 1, true) ~= nil and #fake.sent == before
)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
n = arrow("<Up>")
settle(n)
check(
  "история: второе <Up> — предыдущая, дубль схлопнут",
  buf_text() == "two",
  buf_text()
)
n = arrow("<Up>")
settle(n)
check(
  "история: третье <Up> — самая старая, чужого проекта нет",
  buf_text() == "one",
  buf_text()
)
local cnt = #fake.sent
arrow("<Up>")
sync()
check(
  "история: <Up> на самой старой ничего не делает",
  buf_text() == "one" and #fake.sent == cnt
)
n = arrow("<Down>")
settle(n)
check("история: <Down> — следующая запись", buf_text() == "two", buf_text())
n = arrow("<Down>")
settle(n)
n = arrow("<Down>")
settle(n)
check(
  "история: <Down> за самой новой возвращает черновик",
  buf_text() == "",
  buf_text()
)

-- Черновик сохраняется; правка пользователем сбрасывает позицию.
set_input({ "черновик" })
vim.cmd("startinsert")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
n = arrow("<Up>")
settle(n)
check(
  "история: с черновиком <Up> берёт последнюю запись",
  buf_text():find("три", 1, true) == 1,
  buf_text()
)
n = arrow("<Down>")
settle(n)
check("история: <Down> возвращает черновик", buf_text() == "черновик", buf_text())
set_input({ "правка" })
check("история: правка пользователем сбрасывает позицию", st.hist == nil)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
n = arrow("<Up>")
settle(n)
n = arrow("<Down>")
settle(n)
check(
  "история: после сброса черновик — новая правка",
  buf_text() == "правка",
  buf_text()
)

-- Нет файла или каталога панели: клавиши ведут себя как обычно.
set_input({ "a", "b" })
st.hist = nil
ci.HISTORY_PATH = dir .. "/missing.jsonl"
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local replies = st.hist_replies or 0
arrow("<Up>")
wait(function()
  return (st.hist_replies or 0) > replies
end)
check("история: нет файла — буфер не тронут", buf_text() == "a\nb" and st.hist == nil)
ci.HISTORY_PATH = hist_path
fake.cwd = nil
local replies = st.hist_replies or 0
arrow("<Up>")
wait(function()
  return (st.hist_replies or 0) > replies
end)
check(
  "история: нет cwd — буфер не тронут",
  buf_text() == "a\nb" and st.hist == nil,
  { buf_text(), st.hist }
)
fake.cwd = "/proj/a"
set_input({})

io.stdout:write(failed == 0 and "ALL OK\n" or ("FAILED " .. failed .. "\n"))
vim.cmd(failed == 0 and "qa!" or "cq!")
