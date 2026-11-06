-- Проверка сгенерированной таблицы: пары физических клавиш (опыт 10 проекта) и
-- принятие langmap испытуемым nvim.
-- Запуск: cd <корень плагина> && nvim --headless --clean -u NONE -l tests/table_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = here .. "/../lua/?.lua;" .. package.path
local D = dofile(here .. "/harness/drv.lua")
local T = require("ru-layout.table")

local pairs_ru = {
  { "й", "q" },
  { "Й", "Q" },
  { "ы", "s" },
  { "ё", "`" },
  { "Ё", "~" },
  { "х", "[" },
  { "Х", "{" },
  { "ъ", "]" },
  { "Ъ", "}" },
  { "ж", ";" },
  { "Ж", ":" },
  { "э", "'" },
  { "Э", '"' },
  { "б", "," },
  { "Б", "<" },
  { "ю", "." },
  { "Ю", ">" },
  { "№", "#" },
}
for _, p in ipairs(pairs_ru) do
  D.row(("ru_to_us %s→%s"):format(p[1], p[2]), p[1], p[2], T.ru_to_us[p[1]])
end

local ascii = { ['"'] = "@", [";"] = "$", [":"] = "^", ["?"] = "&", ["/"] = "|", ["."] = "/", [","] = "?" }
local n, bad = 0, {}
for ru, us in pairs(ascii) do
  n = n + 1
  if T.ru_ascii_to_us[ru] ~= us then
    bad[#bad + 1] = ru
  end
end
D.row("ru_ascii_to_us: 7 знаков", "", { 7, {} }, { n, bad })
D.row("ru_ascii_to_us: нет лишних", "", 7, vim.tbl_count(T.ru_ascii_to_us))

-- langmap принимается Neovim; «Эфнн» = "ayy, «о» = j.
D.start({})
D.lua("vim.o.langmap = ...", T.langmap)
D.check("langmap принят", T.langmap, D.lua("return vim.o.langmap"))
D.reset({ "строка", "вторая" })
D.input("Эфнн")
D.sync()
D.check("Эфнн кладёт строку в регистр a", "строка\n", D.lua("return vim.fn.getreg('a')"))
D.reset({ "один", "два" })
D.input("о")
D.sync()
D.check("о = j", 2, D.cursor()[1])
D.stop()
D.finish()
