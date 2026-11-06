-- Ответы встроенных запросов: confirm(), :s///c, inputlist(), -- More --.
-- confirm() без UI сразу возвращает вариант по умолчанию, поэтому испытуемый nvim
-- запускается со своим TUI в псевдотерминале, а запросы идут по сокету --listen.
-- Запуск: cd <корень плагина> && nvim -l tests/dialogs_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = here .. "/../lua/?.lua;" .. package.path
local D = dofile(here .. "/harness/drv.lua")
local FOREVER = 2 ^ 31 - 1

local tmp, job

-- Испытуемый nvim в псевдотерминале. dialogs = true — с модулем dialogs.
local function start(dialogs)
  tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p", tonumber("700", 8))
  local sock = tmp .. "/nvim.sock"
  local ready = tmp .. "/ready"
  -- Сокет появляется в начале запуска, а запросы обслуживаются и до конца init.lua;
  -- отметка ready пишется командой -c после init.lua.
  local cmd = { "nvim", "--clean", "-n", "-i", "NONE", "-u", D.here .. "/init.lua", "--listen", sock }
  vim.list_extend(cmd, { "-c", "call writefile([], " .. vim.fn.string(ready) .. ")" })
  job = vim.fn.jobstart(cmd, {
    pty = true,
    width = 100,
    height = 30,
    env = {
      EXP_LANGMAP = "1",
      EXP_PLUGINS = "",
      XDG_CONFIG_HOME = tmp .. "/config",
      XDG_DATA_HOME = tmp .. "/data",
      XDG_STATE_HOME = tmp .. "/state",
      XDG_CACHE_HOME = tmp .. "/cache",
      XDG_RUNTIME_DIR = tmp,
      HYPRLAND_INSTANCE_SIGNATURE = "",
    },
    on_stdout = function() end,
  })
  assert(job > 0, "nvim не запустился")
  -- TUI ждёт ответов терминала на запросы DA1 и DSR, без них ввод не обрабатывается.
  vim.fn.chansend(job, "\27[?62;22c\27[0n")
  -- Ожидание отметки конца запуска: событие процесса, без срока.
  vim.wait(FOREVER, function()
    return vim.uv.fs_stat(ready) ~= nil
  end, 1)
  D.ch = vim.fn.sockconnect("pipe", sock, { rpc = true })
  assert(D.ch > 0, "сокет nvim недоступен")
  D.req("nvim_get_api_info")
  D.lua([[
vim.keymap.set('n', '<F6>', function() _G.C = vim.fn.confirm('Записать?', "&Yes\n&No\n&Cancel") end)
vim.keymap.set('n', '<F7>', function() _G.C = vim.fn.confirm('Записать?', "&Да\n&Нет") end)
vim.keymap.set('n', '<F8>', function() _G.C = vim.fn.inputlist({ 'Выбор:', '1. a', '2. b' }) end)
]])
  if dialogs then
    D.lua("require('ru-layout.dialogs').setup()")
  end
end

local function stop()
  pcall(vim.rpcnotify, D.ch, "nvim_command", "qa!")
  vim.fn.jobwait({ job }, FOREVER)
  pcall(vim.fn.chanclose, D.ch)
  D.ch = nil
  vim.fn.delete(tmp, "rf")
end

-- Ввод до ответа: после каждой клавиши — режим (запрос обрабатывается после ввода).
local function feed(keys)
  for _, k in ipairs(keys) do
    D.input(k)
    D.sync()
  end
end

local function result()
  return D.lua("local c = _G.C; _G.C = nil; return c")
end

local function lines_after(keys, text)
  D.reset(text)
  feed(keys)
  local m = D.mode().mode
  if m ~= "n" then
    feed({ "<Esc>" })
  end
  return { m, D.lines() }
end

-- Опыт без модуля: применяется ли langmap к букве-ответу.
start(false)
feed({ "<F6>", "н" })
D.row("опыт без модуля: confirm() и н", "<F6>н", "r?", D.mode().mode)
feed({ "<Esc>" })
D.row("опыт без модуля: confirm() Esc", "<Esc>", 0, result())
feed({ "<F6>", "y" })
D.row("опыт без модуля: confirm() y", "<F6>y", 1, result())
D.row(
  "опыт без модуля: :s///c и н — ответ не принят",
  ":s/a/b/gc<CR>н",
  { "r?", { "a a a" } },
  lines_after({ ":s/a/b/gc<CR>", "н" }, { "a a a" })
)
feed({ "<F8>", "2<CR>" })
D.row("опыт без модуля: inputlist() цифра", "<F8>2<CR>", 2, result())
-- Русские клавиши ответа confirm() встроенный запрос не принимает и без модуля.
feed({ "<F7>", "н" })
D.row("опыт без модуля: confirm('&Да\\n&Нет') и н", "<F7>н", "r?", D.mode().mode)
feed({ "<Esc>" })
result()
stop()

-- С модулем dialogs.
start(true)
feed({ "<F6>", "н" })
D.row("confirm(): н = y", "<F6>н", 1, result())
feed({ "<F6>", "т" })
D.row("confirm(): т = n", "<F6>т", 2, result())
feed({ "<F6>", "С" })
D.row("confirm(): С = C", "<F6>С", 3, result())
feed({ "<F6>", "<Esc>" })
D.row("confirm(): Esc", "<F6><Esc>", 0, result())
feed({ "<F6>", "<CR>" })
D.row("confirm(): Enter — по умолчанию", "<F6><CR>", 1, result())
feed({ "<F6>", "n" })
D.row("confirm(): латиница", "<F6>n", 2, result())
feed({ "<F8>", "2<CR>" })
D.row("inputlist(): цифра", "<F8>2<CR>", 2, result())
D.row(
  "normal: н после запроса — снова langmap",
  "нн",
  "no",
  (function()
    D.reset({ "a" })
    D.input("н")
    local m = D.mode().mode
    D.input("<Esc>")
    D.sync()
    return m
  end)()
)

local TEXT = { "a a a", "a a" }
D.row(
  ":s///gc: н т н ф",
  ":%s/a/b/gc<CR>нтнф",
  { "n", { "b a b", "b b" } },
  lines_after({ ":%s/a/b/gc<CR>", "н", "т", "н", "ф" }, TEXT)
)
D.row(
  ":s///gc: н й",
  ":s/a/b/gc<CR>нй",
  { "n", { "b a a" } },
  lines_after({ ":s/a/b/gc<CR>", "н", "й" }, { "a a a" })
)
D.row(
  ":s///gc: д (last)",
  ":s/a/b/gc<CR>д",
  { "n", { "b a a" } },
  lines_after({ ":s/a/b/gc<CR>", "д" }, { "a a a" })
)
D.row(
  ":s///gc: Esc",
  ":s/a/b/gc<CR>н<Esc>",
  { "n", { "b a a" } },
  lines_after({ ":s/a/b/gc<CR>", "н", "<Esc>" }, { "a a a" })
)
D.row(
  ":s///gc: латиница y n",
  ":s/a/b/gc<CR>yny",
  { "n", { "b a b" } },
  lines_after({ ":s/a/b/gc<CR>", "y", "n", "y" }, { "a a a" })
)
D.row(
  ":s///gc: русский текст замены",
  ":s/a/ж/gc<CR>ф",
  { "n", { "ж ж ж" } },
  lines_after({ ":s/a/ж/gc<CR>", "ф" }, { "a a a" })
)

-- Приглашение -- More -- читает клавиши мимо vim.on_key: й не переводится (остаток).
D.reset({ "" })
feed({ ':echo join(range(1, 100), "\\n")<CR>' })
local m1 = D.mode().mode
feed({ "й" })
local m2 = D.mode().mode
feed({ "q" })
D.row(
  "-- More --: й не принимается, q — да (остаток)",
  "rm → й → q",
  { "rm", "rm", "n" },
  { m1, m2, D.mode().mode }
)
stop()
D.finish()
