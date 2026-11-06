-- Терминальные буферы: перевод кириллических клавиш для TUI из списка (lazygit и
-- другие программы с латинскими горячими клавишами) буферными привязками
-- терминального режима `tnoremap ы s`. Системная раскладка не переключается;
-- shell и всё вне списка привязок не получают.
--
-- Программа определяется двумя способами, оба по событию:
--  1. по команде в имени буфера `term://<cwd>//<pid>:<команда>` на `TermOpen`
--     (так запускает Snacks.lazygit): постоянные привязки на жизнь буфера;
--  2. по заголовку терминала (OSC 0/2, событие `TermRequest`) для программы,
--     запущенной из shell: привязки включаются, пока заголовок назван по программе
--     из списка, и снимаются, когда заголовок сменился (так делает prompt shell
--     после выхода программы). Работает, только если программа или shell
--     выставляют заголовок.
local M = {}

local DEFAULTS = { programs = { "lazygit" } }

M.opts = vim.deepcopy(DEFAULTS)
M.group = nil
-- Буферы с включёнными привязками: buf → "name" | "title".
M.active = {}

local function pairs_map()
  return require("ru-layout.table").ru_to_us
end

-- Базовое имя первого слова команды: `/usr/bin/lazygit -w x` → `lazygit`.
local function program_of(cmd)
  local first = (cmd or ""):match("^%s*(%S+)")
  if not first then
    return nil
  end
  return vim.fn.fnamemodify(first, ":t")
end

-- Команда из имени терминального буфера `term://<cwd>//<pid>:<команда>`.
function M.name_program(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local cmd = name:match("^term://.-//%d+:(.*)$")
  return program_of(cmd)
end

local function listed(prog)
  return prog ~= nil and vim.tbl_contains(M.opts.programs, prog)
end

local DESC = "ru-layout: терминал"

local function set_pairs(buf)
  for ru, us in pairs(pairs_map()) do
    -- № парой не считается: у него нет клавиши в us.
    if ru ~= "№" then
      vim.keymap.set("t", ru, us, { buffer = buf, nowait = true, desc = DESC })
    end
  end
end

local function del_pairs(buf)
  for ru in pairs(pairs_map()) do
    pcall(vim.keymap.del, "t", ru, { buffer = buf })
  end
end

-- Переключатель перевода в буфере: `<M-l>` снимает и ставит привязки по паре, чтобы
-- набрать русский текст внутри программы (сообщение коммита в lazygit, поиск).
-- Состояние — переменная буфера `ru_layout_terminal_off`.
local function toggle(buf)
  if vim.b[buf].ru_layout_terminal_off then
    vim.b[buf].ru_layout_terminal_off = false
    set_pairs(buf)
  else
    vim.b[buf].ru_layout_terminal_off = true
    del_pairs(buf)
  end
end

-- Включить привязки кириллица → латиница в терминальном режиме буфера.
function M.enable(buf, kind)
  if M.active[buf] then
    return
  end
  vim.b[buf].ru_layout_terminal_off = false
  set_pairs(buf)
  vim.keymap.set("t", "<M-l>", function()
    toggle(buf)
  end, { buffer = buf, desc = "ru-layout: переключатель перевода в терминале" })
  M.active[buf] = kind
end

function M.disable(buf)
  if not M.active[buf] then
    return
  end
  M.active[buf] = nil
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.b[buf].ru_layout_terminal_off = false
  del_pairs(buf)
  pcall(vim.keymap.del, "t", "<M-l>", { buffer = buf })
end

-- Заголовок из OSC 0/2: `\27]0;текст` или `\27]2;текст`.
local function osc_title(seq)
  return seq:match("^\27%]0;(.*)$") or seq:match("^\27%]2;(.*)$")
end

function M.setup(opts)
  -- Список программ заменяется целиком: он берётся из opts или из DEFAULTS.
  M.opts = { programs = vim.deepcopy((opts and opts.programs) or DEFAULTS.programs) }
  M.group = vim.api.nvim_create_augroup("ru-layout-terminal", { clear = true })

  vim.api.nvim_create_autocmd("TermOpen", {
    group = M.group,
    callback = function(ev)
      if listed(M.name_program(ev.buf)) then
        M.enable(ev.buf, "name")
      end
    end,
  })

  vim.api.nvim_create_autocmd("TermRequest", {
    group = M.group,
    callback = function(ev)
      -- Программа, найденная по команде буфера, остаётся на всю жизнь буфера.
      if M.active[ev.buf] == "name" then
        return
      end
      local seq = type(ev.data) == "table" and ev.data.sequence or ev.data
      local title = type(seq) == "string" and osc_title(seq) or nil
      if not title then
        return
      end
      if listed(program_of(title)) then
        M.enable(ev.buf, "title")
      else
        M.disable(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TermClose", "BufWipeout" }, {
    group = M.group,
    callback = function(ev)
      M.active[ev.buf] = nil
    end,
  })

  -- Уже открытые терминалы (повторный setup, setup после открытия буферов).
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "terminal" and listed(M.name_program(buf)) then
      M.enable(buf, "name")
    end
  end
end

return M
