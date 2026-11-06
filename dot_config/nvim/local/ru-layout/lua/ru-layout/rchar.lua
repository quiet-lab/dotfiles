-- Обёртка `r`: аргумент замены по раскладке.
--
-- Аргумент `r` — текст, `langmap` к нему не применяется: в русской раскладке
-- `rf` над латинским словом ставит «а». Правило обёртки: в русской раскладке
-- `r` с кириллической буквой над латинской буквой ставит символ той же клавиши
-- в английской раскладке (`rа` над `abc` → `fbc`, `3rх` над `abcd` → `[[[d`);
-- над кириллицей, цифрой, знаком и пустой строкой — букву как набрана
-- (`rф` над `абв` → `фбв`).
-- В английской раскладке и для прочих аргументов (`<CR>`, `<C-v>…`, `<Esc>`,
-- цифры, знаки) `r` работает как встроенный.
--
--   require("ru-layout.rchar").setup()  -- привязки `r` и `к` в normal и visual (x)
--
-- `к` — та же клавиша в русской раскладке. `langmap` к привязкам не ведёт
-- (`к` дал бы встроенный `r`), поэтому привязка `к` ставится здесь же, не
-- полагаясь на дубли модуля keymap.
--
-- `gr` не трогается: в LazyVim это привязка LSP (ссылки).
local tr = require("ru-layout.tr")

local M = {}

local DESC = "ru-layout: r (замена символа по раскладке)"

local function layout_code()
  local ok, layout = pcall(require, "ru-layout.layout")
  return ok and layout.get() or nil
end

-- Символ под курсором (в visual — под курсором, а не в начале выделения).
local function char_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  return vim.fn.strpart(line, col, 1, true)
end

-- Аргумент замены после перевода по правилу.
function M.translate(c)
  if layout_code() ~= "ru" then
    return c
  end
  local us = tr.ru2us[c]
  if not us or not tr.is_cyrillic(c) then
    return c
  end
  if not char_under_cursor():match("^[A-Za-z]$") then
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
  for _, lhs in ipairs({ "r", tr.lhs_to_ru("r") }) do
    vim.keymap.set({ "n", "x" }, lhs, M.expr, { expr = true, replace_keycodes = false, desc = DESC })
  end
end

return M
