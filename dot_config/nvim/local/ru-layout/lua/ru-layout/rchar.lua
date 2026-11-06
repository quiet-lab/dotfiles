-- Обёртка `r`: аргумент замены по раскладке.
--
-- Аргумент `r` — текст, `langmap` к нему не применяется: в русской раскладке
-- `rf` над латинским словом ставит «а». Правило обёртки: в русской раскладке
-- `r` с кириллической буквой над латинской буквой ставит символ той же клавиши
-- в английской раскладке (`rа` над `abc` → `fbc`, `3rх` над `abcd` → `[[[d`);
-- над кириллицей, цифрой, знаком и пустой строкой — букву как набрана
-- (`rф` над `абв` → `фбв`). В visual решение принимается по всему выделению:
-- перевод, если в нём есть латинская буква и нет кириллицы (`v$rа` над `abc1` →
-- `ffff`, над `abcд` → `аааа`).
-- В английской раскладке и для прочих аргументов (`<CR>`, `<C-v>…`, `<Esc>`,
-- цифры, знаки) `r` работает как встроенный.
--
--   require("ru-layout.rchar").setup()  -- привязка `r` в normal и visual (x)
--
-- `к` — та же клавиша в русской раскладке. `langmap` к привязкам не ведёт
-- (`к` дал бы встроенный `r`); дубль `к` ставит модуль keymap, поэтому
-- keymap.install() вызывается раньше этого модуля.
--
-- `gr` не трогается: в LazyVim это привязка LSP (ссылки).
local tr = require("ru-layout.tr")

local M = {}

local DESC = "ru-layout: r (замена символа по раскладке)"

-- Символ под курсором.
local function char_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  return vim.fn.strpart(line, col, 1, true)
end

-- Текст выделения в visual (символьном, строчном, блочном); nil вне visual.
local function selection()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
  return ok and table.concat(lines, "\n") or ""
end

-- Ожидается ли латиница там, где идёт замена: в normal — латинская буква под
-- курсором, в visual — в выделении есть латинская буква и нет кириллицы.
local function latin_context()
  local sel = selection()
  if sel then
    return sel:find("[A-Za-z]") ~= nil and not tr.has_cyrillic(sel)
  end
  return char_under_cursor():match("^[A-Za-z]$") ~= nil
end

-- Аргумент замены после перевода по правилу.
function M.translate(c)
  if tr.layout() ~= "ru" then
    return c
  end
  local us = tr.ru2us[c]
  if not us or not tr.is_cyrillic(c) then
    return c
  end
  if not latin_context() then
    return c
  end
  return us
end

-- Тело привязки `r` (expr): читает аргумент и возвращает `r<символ>`. Счётчик
-- уже набран до привязки и остаётся в силе (`3rх`).
function M.expr()
  local ok, c = pcall(vim.fn.getcharstr)
  if not ok or c == "" then
    -- Прерывание (<C-c>): как встроенный `r<Esc>` — ничего не менять.
    return "r\27"
  end
  return "r" .. M.translate(c)
end

function M.setup()
  -- replace_keycodes = false: аргумент подаётся как есть (`<`, байты специальных
  -- клавиш); vim.keymap.set заменяет прежнюю привязку, повтор ничего не множит.
  vim.keymap.set({ "n", "x" }, "r", M.expr, { expr = true, replace_keycodes = false, desc = DESC })
end

return M
