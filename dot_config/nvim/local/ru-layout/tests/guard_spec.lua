-- Сторожевой тест потребителей getchar: ищет в установленных плагинах строки, где
-- плагин сам читает клавиши (`ru-layout.plugins.pattern`), и сверяет найденное
-- с перечнем `M.consumers` ∪ `M.ignored` в ru-layout.plugins: по каждому плагину —
-- файлы и число строк в каждом. Новый плагин, новый файл или изменившееся число
-- строк — падение с именем плагина: точку нужно разобрать и обернуть либо внести
-- в M.ignored с причиной, затем обновить числа.
-- Каталог плагинов — ~/.local/share/nvim/lazy (или $RU_LAYOUT_LAZY_DIR).
-- Запуск: cd <корень плагина> && nvim -l tests/guard_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = here .. "/../lua/?.lua;" .. package.path
local D = dofile(here .. "/harness/drv.lua")
local P = require("ru-layout.plugins")

local dir = vim.fs.normalize(vim.env.RU_LAYOUT_LAZY_DIR or vim.fn.expand("~/.local/share/nvim/lazy"))

-- Поиск: ripgrep по *.lua и *.vim; код 1 — совпадений нет.
local res = vim
  .system({
    "rg",
    "--no-heading",
    "--line-number",
    "--no-config",
    "--glob",
    "*.lua",
    "--glob",
    "*.vim",
    "-e",
    P.pattern,
    dir,
  }, { text = true })
  :wait()
D.check("rg отработал", true, res.code == 0 or res.code == 1)

-- found[плагин][файл] = число строк. Комментарии и каталоги тестов плагинов не
-- считаются: они не читают клавиши в работе.
local found = {}
for _, line in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
  local path, text = line:match("^(.-):%d+:(.*)$")
  if path and not text:match("^%s*%-%-") and not text:match('^%s*"') then
    local rel = path:sub(#dir + 2)
    local plugin, file = rel:match("^([^/]+)/(.+)$")
    local is_test = ("/" .. file):match("/tests?/") or ("/" .. file):match("/spec/")
    if plugin and not is_test then
      found[plugin] = found[plugin] or {}
      found[plugin][file] = (found[plugin][file] or 0) + 1
    end
  end
end

-- Перечень модуля: обёрнутые и известные без обёртки; плагин не может быть в обоих.
local function sorted_pairs(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys)
  local i = 0
  return function()
    i = i + 1
    return keys[i], t[keys[i]]
  end
end
local expected, kind = {}, {}
for name, c in sorted_pairs(P.consumers) do
  expected[name] = c.points
  kind[name] = "обёрнут"
  D.check(
    "перечень: у " .. name .. " есть apply и how",
    true,
    type(c.apply) == "function" and type(c.how) == "string"
  )
end
for name, c in sorted_pairs(P.ignored) do
  D.check("перечень: " .. name .. " не в обоих списках", nil, kind[name])
  expected[name] = c.points
  kind[name] = "без обёртки"
  D.check(
    "перечень: у " .. name .. " указана причина",
    true,
    type(c.reason) == "string" and c.reason ~= ""
  )
end

local names = {}
for name in pairs(found) do
  names[name] = true
end
for name in pairs(expected) do
  names[name] = true
end
local sorted = vim.tbl_keys(names)
table.sort(sorted)

for _, name in ipairs(sorted) do
  local exp, fact = expected[name], found[name]
  if not exp then
    D.row("новый потребитель getchar: " .. name, "", "нет в перечне", fact, false)
  elseif not fact and vim.fn.isdirectory(dir .. "/" .. name) == 0 then
    -- Плагин удалён из установки: запись перечня не мешает, но и не проверяется.
    D.row(name .. " (" .. kind[name] .. ")", "", "не установлен", "не установлен", true)
  else
    D.row(name .. " (" .. kind[name] .. ")", "", exp, fact or {})
  end
end

D.finish()
