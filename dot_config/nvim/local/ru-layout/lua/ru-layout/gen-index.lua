-- Генератор перечня встроенных сочетаний с Ctrl из `$VIMRUNTIME/doc/index.txt`:
-- записи `CTRL-…` по режимам, в том числе многоклавишные (`i_CTRL-X_CTRL-N`,
-- `c_CTRL-R_CTRL-W`, `CTRL-W_…`, `g_CTRL-G`). Перечень нужен модулю chords
-- (продолжения сочетаний, которые Neovim читает мимо привязок) и тесту
-- `chords_spec.lua` (обе формы кодирования каждой записи дают одно состояние).
-- Запуск: nvim -l gen-index.lua [index.txt] <выход.lua>
-- Без первого аргумента берётся index.txt запущенного nvim; insert.txt и cmdline.txt
-- читаются из того же каталога. После генерации файл
-- форматируется stylua, как у gen-table.lua.
local src, out = arg[1], arg[2]
if not out then
  src, out = vim.env.VIMRUNTIME .. "/doc/index.txt", arg[1]
end
assert(out, "nvim -l gen-index.lua [index.txt] <выход.lua>")

-- Разделы index.txt → режим. Разделы 2–2.5 — normal, 2.6 — operator-pending,
-- 3 — visual (`x`; select пользуется теми же записями), 5 — terminal: в нём нет
-- таблицы, записи берутся из ссылок `|t_CTRL-\_CTRL-O|` в тексте.
local SECTIONS = {
  ["1"] = "i",
  ["2"] = "n",
  ["2.1"] = "n",
  ["2.2"] = "n",
  ["2.3"] = "n",
  ["2.4"] = "n",
  ["2.5"] = "n",
  ["2.6"] = "o",
  ["3"] = "x",
  ["4"] = "c",
  ["5"] = "t",
}

-- Лексема столбца клавиш → запись Neovim (`CTRL-X` → `<C-x>`,
-- `CTRL-SHIFT-V` → `<C-S-v>`, `CTRL-<Tab>` → `<C-Tab>`); nil — не клавиша.
local function token(t)
  local key = t:match("^CTRL%-SHIFT%-(.)$")
  if key then
    return "<C-S-" .. key:lower() .. ">"
  end
  key = t:match("^CTRL%-<([%w-]+)>$")
  if key then
    return "<C-" .. key .. ">"
  end
  key = t:match("^CTRL%-(.)$")
  if key then
    return "<C-" .. key:lower() .. ">"
  end
  if t:match("^{%w+}$") or t:match("^<[%w-]+>$") then
    return t
  end
  if #t == 1 then
    return t
  end
  return nil
end

-- Столбец клавиш: лексемы до первой, которая клавишей не является (описание,
-- отделённое одним пробелом: `CTRL-V {number} insert three digit…`).
local function keys_of(field)
  local seq = {}
  for t in field:gmatch("%S+") do
    local k = token(t)
    if not k then
      break
    end
    seq[#seq + 1] = k
  end
  return seq
end

-- Имя метки → лексемы (`t_CTRL-\_CTRL-O` → `<C-\>`, `<C-o>`).
local function keys_of_tag(tag)
  local body = tag:gsub("^%l_", "")
  local seq = {}
  for t in (body .. "_"):gmatch("(CTRL%-.-)_") do
    seq[#seq + 1] = token(t)
  end
  return seq
end

local function has_ctrl(seq)
  for _, k in ipairs(seq) do
    if k:find("^<C%-") then
      return true
    end
  end
  return false
end

local result = { i = {}, n = {}, o = {}, x = {}, c = {}, t = {} }
local seen = {}
local function add(mode, seq)
  if #seq == 0 or not has_ctrl(seq) then
    return
  end
  local id = mode .. "\0" .. table.concat(seq, " ")
  if not seen[id] then
    seen[id] = true
    table.insert(result[mode], seq)
  end
end

local mode
for line in io.lines(src) do
  local num = line:match("^(%d[%d.]*)%s+%S")
  if num and SECTIONS[num:gsub("%.$", "")] ~= nil then
    mode = SECTIONS[num:gsub("%.$", "")]
  elseif num and line:match("^6%.") then
    mode = nil -- раздел 6 — команды Ex
  end
  if mode == "t" then
    for tag in line:gmatch("|([^|%s]*CTRL[^|%s]*)|") do
      add("t", keys_of_tag(tag))
    end
  elseif mode then
    local rest = line:match("^|[^|]+|%s*(.*)$")
    if rest then
      add(mode, keys_of(rest:match("^([^\t]*)")))
    end
  end
end

-- Есть ли в режиме запись, которая начинается с seq (`<C-r><C-o>{register}` для
-- метки `i_CTRL-R_CTRL-O`).
local function has_longer(m, seq)
  for _, e in ipairs(result[m]) do
    if #e > #seq and table.concat(e, " ", 1, #seq) == table.concat(seq, " ") then
      return true
    end
  end
  return false
end

-- Многоклавишные сочетания из одних Ctrl, которых нет в index.txt (объекты
-- `c_CTRL-R_CTRL-W`, `c_CTRL-R_CTRL-A`, `i_CTRL-\_CTRL-O`): метки справки insert.txt
-- и cmdline.txt.
local doc = vim.fn.fnamemodify(src, ":h")
for file, m in pairs({ ["insert.txt"] = "i", ["cmdline.txt"] = "c" }) do
  local path = doc .. "/" .. file
  if vim.uv.fs_stat(path) then
    for line in io.lines(path) do
      for tag in line:gmatch("%*(" .. m .. "_CTRL%-[^*%s]+)%*") do
        -- Только «CTRL-x_CTRL-y[_…]»: шаблоны Lua не повторяют группу, поэтому
        -- лексемы снимаются по одной.
        local rest, n = tag:sub(3), 0
        while rest:match("^CTRL%-.") do
          rest, n = rest:sub(7):gsub("^_", ""), n + 1
        end
        local seq = keys_of_tag(tag)
        if rest == "" and n >= 2 and not has_longer(m, seq) then
          add(m, seq)
        end
      end
    end
  end
end

local count = 0
for _, list in pairs(result) do
  table.sort(list, function(a, b)
    return table.concat(a, " ") < table.concat(b, " ")
  end)
  count = count + #list
end

local f = assert(io.open(out, "w"))
f:write(
  "-- Создано gen-index.lua из $VIMRUNTIME/doc/index.txt ("
    .. vim.split(vim.fn.execute("version"), "\n")[2]
    .. ")\n-- Записи с Ctrl по режимам; лексема — клавиша в записи Neovim,"
    .. "\n-- {…} — аргумент (регистр, символ). Не править руками.\nreturn "
)
f:write(vim.inspect(result))
f:write("\n")
f:close()
print(("entries=%d"):format(count))

local stylua = vim.fn.exepath("stylua")
if stylua == "" then
  local mason = vim.fn.expand("~/.local/share/nvim/mason/bin/stylua")
  stylua = vim.fn.executable(mason) == 1 and mason or nil
end
if stylua then
  local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"):match("^(.*)/lua/ru%-layout/[^/]*$") or "."
  local r = vim.system({ stylua, "--config-path", here .. "/stylua.toml", out }):wait()
  if r.code ~= 0 then
    io.stderr:write("stylua: " .. (r.stderr or "") .. "\n")
    os.exit(1)
  end
else
  print("stylua не найден: отформатируйте выходной файл вручную")
end
