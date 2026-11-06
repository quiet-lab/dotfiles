-- Обёртка `@`: воспроизведение макросов, записанных в русской раскладке.
--
-- При записи в русской раскладке в регистр попадают кириллические клавиши
-- (`йфчй` — регистр a = «ч»). Встроенный `@` подаёт содержимое регистра как ввод
-- из отображения, а к такому вводу `langmap` применяется только при включённой
-- 'langremap' (по умолчанию она выключена), поэтому встроенный `@a` такой макрос
-- не воспроизводит. Обёртка читает имя регистра сама, переводит его по физической
-- клавише и вызывает встроенный `@` с включённой на время выполнения
-- 'langremap': `langmap` и кириллические дубли привязок переводят клавиши
-- макроса так же, как при записи.
--
--   require("ru-layout.macro").setup()  -- привязка `@` в normal
--
-- Имя регистра: кириллица — по физической клавише (`@ф` = `@a`, `@Ж` = `@:`);
-- в русской раскладке ASCII-знаки — тоже по клавише (`@"` = `@@`, так как `"`
-- стоит на клавише `@`). `@@`, `@:`, счётчик, `reg_executing()` и запись
-- макроса с вложенным `@a` — как у встроенного `@`, потому что выполняет его он.
local tr = require("ru-layout.tr")
local T = require("ru-layout.table")

local M = {}

local DESC = "ru-layout: @ (макрос из регистра)"

-- Имя регистра по физической клавише.
function M.register_name(c)
  if tr.ru2us[c] then
    return tr.ru2us[c]
  end
  if tr.layout() == "ru" and T.ru_ascii_to_us[c] then
    return T.ru_ascii_to_us[c]
  end
  return c
end

-- Выполнить `count@r` встроенным `@` с включённой 'langremap'.
function M.exec(r, count)
  local saved = vim.o.langremap
  vim.o.langremap = true
  -- «n» — встроенный `@`, а не эта привязка; содержимое регистра встроенный `@`
  -- всё равно подаёт с привязками. «i» — перед остатком ввода (`:normal @ax`),
  -- «x» — выполнить сразу, пока действует 'langremap'; без «x» завершающий <Esc>
  -- макроса ждал бы следующей клавиши (проверка D3 проекта). Флаг «t» не нужен
  -- и вреден: набранный <Esc>, за которым в очереди сразу идёт клавиша,
  -- Neovim читает как сочетание с Alt, а набранные клавиши попадают в
  -- записываемый макрос.
  local ok, err = pcall(vim.api.nvim_feedkeys, (count or 1) .. "@" .. r, "inx", false)
  vim.o.langremap = saved
  if not ok then
    error(err, 0)
  end
end

-- Тело привязки `@`.
function M.play()
  local count = vim.v.count1
  local ok, c = pcall(vim.fn.getcharstr)
  if not ok or c == "\27" or c == "" then
    return
  end
  M.exec(M.register_name(c), count)
end

function M.setup()
  -- vim.keymap.set заменяет прежнюю привязку, повторный вызов ничего не множит.
  vim.keymap.set("n", "@", M.play, { desc = DESC })
end

return M
