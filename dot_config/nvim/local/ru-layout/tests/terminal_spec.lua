-- Терминальные буферы: ru-layout.terminal на оснастке.
-- Запуск: cd <корень плагина> && nvim -l tests/terminal_spec.lua
-- Программа `cat` стоит в списке вместо lazygit: она печатает эхом то, что получила,
-- поэтому по тексту буфера видно, какие байты дошли до процесса. Ожидания — vim.wait
-- с условием по содержимому буфера (до события продукта), без сроков.
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

local function eq(name, expect, fact)
  D.row(name, "", expect, fact)
end

D.start({})
D.lua([[require("ru-layout.terminal").setup({ programs = { "cat", "lazygit" } })]])

-- Новый терминальный буфер с командой в текущем окне, терминальный режим.
-- Возврат — после появления первой строки вывода (или сразу, если вывода не ждём).
local function open(cmd)
  D.lua(
    [[local cmd = ...
    vim.cmd("enew")
    vim.fn.jobstart(cmd, { term = true })
    vim.cmd("startinsert")
    return vim.api.nvim_get_current_buf()]],
    cmd
  )
  D.sync()
end

-- Ждать, пока в тексте буфера появится подстрока; вернуть текст терминала.
local function wait_text(sub)
  return D.lua(
    [[local sub = ...
    local function text() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") end
    vim.wait(2 ^ 31 - 1, function() return text():find(sub, 1, true) ~= nil end, 1)
    return text()]],
    sub
  )
end

local function has(text, sub)
  return text:find(sub, 1, true) ~= nil
end

local function tmaps()
  return D.lua([[local n = 0
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "t")) do if m.desc == "ru-layout: терминал" then n = n + 1 end end
    return n]])
end

local function mode()
  return D.lua("return vim.api.nvim_get_mode().mode")
end

-- 1. cat из списка: кириллица переводится по паре.
open({ "cat" })
D.input("ыф")
eq("cat в списке: ыф → sa", true, has(wait_text("sa"), "sa"))
eq("cat в списке: привязок 66", 66, tmaps())
D.input("<CR>")
D.sync()

-- 2. Ё/ё → ~ и `, заглавные — по регистру.
open({ "cat" })
D.input("ёЁФ")
local t = wait_text("`~A")
eq("Ё/ё/Ф → `~A", true, has(t, "`~A"))

-- 3. <Esc> и <C-\><C-n> выходят из терминального режима.
D.input("<Esc>")
eq("<Esc> посылается программе, режим t", "t", mode())
D.input("<C-\\><C-n>")
D.sync()
eq("<C-\\><C-n> выходит в normal", "nt", mode())

-- 4. Команда не из списка: привязок нет, кириллица доходит как есть.
open({ "bash", "-c", "cat" })
eq("bash: привязок нет", 0, tmaps())
D.input("ыф")
eq("bash: ыф как есть", true, has(wait_text("ыф"), "ыф"))

-- 5. shell по умолчанию: привязок нет.
D.lua([[vim.cmd("enew"); vim.cmd("terminal"); vim.cmd("startinsert")]])
D.sync()
eq("shell по умолчанию: привязок нет", 0, tmaps())
eq(
  "shell по умолчанию: буферных t-привязок нет",
  0,
  D.lua([[return #vim.api.nvim_buf_get_keymap(0, "t")]])
)

-- 6. Привязки не утекают в другой буфер.
D.lua([[vim.cmd("enew")]])
eq("обычный буфер: t-привязок нет", 0, D.lua([[return #vim.api.nvim_buf_get_keymap(0, "t")]]))
open({ "cat" })
D.lua([[vim.cmd("enew")]])
eq(
  "после перехода в другой буфер: нет",
  0,
  D.lua([[return #vim.api.nvim_buf_get_keymap(0, "t")]])
)

-- 7. Программа с путём и аргументами: basename первого слова.
open({ "/usr/bin/cat", "-u" })
eq("путь и аргументы: привязки есть", 66, tmaps())

-- 8. lazygit, если установлен: имя буфера с lazygit даёт привязки.
if vim.fn.executable("lazygit") == 1 then
  D.lua([[vim.cmd("enew"); vim.fn.jobstart({ "lazygit", "--version" }, { term = true })]])
  D.sync()
  eq("lazygit: привязки есть", 66, tmaps())
end

-- 9. Программа из shell: заголовок OSC включает привязки, смена заголовка снимает.
open({
  "bash",
  "-c",
  [[printf '\033]0;lazygit\007'; read x; printf '\033]0;user@host: ~\007'; read y; cat]],
})
local function wait_maps(n)
  return D.lua(
    [[local n = ...
    local function cnt()
      local c = 0
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "t")) do if m.desc == "ru-layout: терминал" then c = c + 1 end end
      return c
    end
    vim.wait(2 ^ 31 - 1, function() return cnt() == n end, 1)
    return cnt()]],
    n
  )
end
eq("заголовок lazygit: привязки включены", 66, wait_maps(66))
D.input("<CR>")
eq("заголовок shell: привязки сняты", 0, wait_maps(0))
D.input("<CR>")
D.input("ыф")
eq("после снятия: ыф как есть", true, has(wait_text("ыф"), "ыф"))

-- 10. Повторный setup не дублирует автокоманды.
D.lua([[local T = require("ru-layout.terminal"); T.setup({ programs = { "cat" } }); T.setup({ programs = { "cat" } })]])
eq(
  "повторный setup: по одной автокоманде TermOpen",
  1,
  D.lua([[return #vim.api.nvim_get_autocmds({ group = "ru-layout-terminal", event = "TermOpen" })]])
)
eq(
  "список заменён целиком",
  { "cat" },
  D.lua([[return require("ru-layout.terminal").opts.programs]])
)

D.stop()
D.finish()
