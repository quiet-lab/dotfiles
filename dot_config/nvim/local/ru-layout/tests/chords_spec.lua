-- Независимость от хоста: каждая запись index.txt с Ctrl (перечень ru-layout.index)
-- в трёх формах — латинской (раскладка US), физической в раскладке RU (так шлёт
-- wezterm: `<C-w>ч`) и символьной в раскладке RU (так шлёт Neovide: `<C-ц>ч`) — даёт
-- одно и то же состояние буфера, окна, командной строки и режима. Кроме того:
-- сверка перечня с генератором, приоритеты алиасов и дублей, порядок установки,
-- сочетания в терминальном буфере, перевод getchar()/getcharstr().
-- Запуск: cd <корень плагина> && nvim --headless --clean -u NONE -l tests/chords_spec.lua
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = here .. "/harness/?.lua;" .. here .. "/../lua/?.lua;" .. package.path
local D = require("drv")
local tr = require("ru-layout.tr")
local INDEX = require("ru-layout.index")

-- 1. Перечень совпадает с тем, что генератор строит из index.txt этого nvim.
do
  local out = vim.fn.tempname() .. ".lua"
  local r = vim.system({ "nvim", "-l", D.root .. "/lua/ru-layout/gen-index.lua", out }, { text = true }):wait()
  D.check("gen-index.lua завершился", 0, r.code)
  D.check("перечень = выход генератора", true, vim.deep_equal(dofile(out), INDEX))
  os.remove(out)
end

-- Формы записи. Аргументы: регистр — `a` (в RU — `ф`), прочие — цифры (текст,
-- одинаковый в обеих раскладках).
local ARG = { ["{char}"] = "1", ["{char1}"] = "1", ["{char2}"] = "2", ["{number}"] = "065", ["{expr}"] = "12<CR>" }
local function cyr_letter(c)
  local ru = tr.us2ru[c]
  return (ru and #ru > 1) and ru or nil
end
local function cyr_mod(t)
  local mods, c = tr.split_mod(t)
  if not mods then
    return nil
  end
  if mods:find("S%-") and c:match("^%l$") then
    local ru = cyr_letter(c:upper())
    return ru and "<" .. mods .. ru .. ">"
  end
  local ru = cyr_letter(c)
  return ru and "<" .. mods .. ru .. ">"
end
-- Записи-префиксы чтецов без аргумента в index.txt (`<C-q>` — «как CTRL-V»): чтец
-- ждёт следующую клавишу, поэтому к записи добавляется буквальный символ.
local NEEDS_ARG = { ["<C-q>"] = true, ["<C-v>"] = true }
-- form: "us" | "phys" (Ctrl латиницей, буквы кириллицей) | "sym" (всё кириллицей).
local function render(e, form)
  local out, translated = {}, false
  if #e == 1 and NEEDS_ARG[e[1]] then
    e = { e[1], "{char}" }
  end
  for _, t in ipairs(e) do
    local k = t
    if t == "{register}" or t == "{regname}" then
      k = form == "us" and "a" or "ф"
    elseif ARG[t] then
      k = ARG[t]
    elseif #t == 1 then
      k = (form ~= "us" and cyr_letter(t)) or (t == "<" and "<lt>" or t)
    elseif form == "sym" and cyr_mod(t) then
      k = cyr_mod(t)
      translated = true
    end
    out[#out + 1] = k
  end
  return table.concat(out), translated
end

-- Записи, которые в испытании не запускаются: выход из nvim (`<C-w>q` в последнем
-- окне), остановка процесса (`<C-z>`), обобщённые аргументы (`{mode}`, `<C-w>{char}`
-- покрыты конкретными записями).
local SKIP = {
  ["<C-z>"] = true,
  ["<C-w>q"] = true,
  ["<C-w><C-q>"] = true,
}
local function skipped(e)
  local s = table.concat(e)
  return SKIP[s] or s:find("{mode}", 1, true) or s == "<C-w>{char}"
end

D.start({})
-- Каталог с файлом «12»: `<C-w>gF` и `<C-w>f` по слову «12» под курсором открывают
-- его, а не завершаются ошибкой (после неудачного `<C-w>gF` Neovim оставляет
-- модификатор вкладки следующему разделению окна).
D.lua([[
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "twelve" }, dir .. "/12")
  vim.cmd.cd(dir)
  require("ru-layout.keymap").install()
  require("ru-layout").setup()
]])

-- Сброс к одному окну, одной вкладке, новому буферу; регистр a и списки переходов.
local function reset(lines, cur)
  D.input("<Esc><Esc>")
  while D.mode().blocking do
    D.input("<Esc>")
  end
  D.sync()
  D.lua(
    [[local lines, cur = ...
    for _, c in ipairs({ "tabonly!", "only!", "enew!", "%bwipe!", "clearjumps" }) do
      pcall(vim.cmd, "silent! " .. c)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, cur)
    vim.fn.setreg("a", "REG")
    vim.v.errmsg = ""]],
    lines,
    cur
  )
end

-- Снимок состояния после ввода.
local function snapshot()
  local st = D.sync()
  if st:match("^BLOCKING") then
    return st
  end
  return D.lua([[
    return {
      mode = vim.fn.mode(1),
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
      cursor = vim.api.nvim_win_get_cursor(0),
      wins = #vim.api.nvim_tabpage_list_wins(0),
      tabs = #vim.api.nvim_list_tabpages(),
      cmd = vim.fn.getcmdtype() .. vim.fn.getcmdline() .. ":" .. vim.fn.getcmdpos(),
      err = vim.v.errmsg,
      pum = vim.fn.pumvisible(),
      reg = vim.fn.getreg('"'),
    }]])
end

-- Контекст режима: текст, курсор, ввод перед записью и после неё.
local CTX = {
  n = { lines = { "alpha beta 12", "gamma delta", "alpha" }, cur = { 1, 11 }, pre = "", post = "" },
  x = { lines = { "alpha beta 12", "gamma 12 delta", "alpha" }, cur = { 1, 11 }, pre = "vj", post = "" },
  o = { lines = { "alpha beta 12", "gamma delta", "alpha" }, cur = { 1, 0 }, pre = "d", post = "j" },
  i = { lines = { "alpha beta 12", "gamma delta", "al" }, cur = { 3, 1 }, pre = "A", post = "" },
  c = { lines = { "alpha beta 12" }, cur = { 1, 0 }, pre = ":abc def", post = "" },
}

-- Ввод режима подаётся отдельно от записи: `<C-c>` в записи — прерывание, оно
-- сбросило бы ещё не разобранный ввод перед ним.
local function run(m, keys)
  local c = CTX[m]
  reset(c.lines, c.cur)
  D.input(c.pre)
  D.sync()
  D.input(keys .. c.post)
  return snapshot()
end

local ONLY = vim.env.CHORDS_ONLY
local total, checked = 0, 0
for _, m in ipairs({ "n", "x", "o", "i", "c" }) do
  if ONLY and not ONLY:find(m, 1, true) then
    goto continue
  end
  for _, e in ipairs(INDEX[m]) do
    if not skipped(e) then
      local us = render(e, "us")
      local sym, translated = render(e, "sym")
      local phys = render(e, "phys")
      if translated or phys ~= us then
        total = total + 1
        local base = run(m, us)
        if phys ~= us then
          D.row(m .. " " .. table.concat(e) .. " физическая", phys, base, run(m, phys))
          checked = checked + 1
        end
        if translated then
          D.row(m .. " " .. table.concat(e) .. " символьная", sym, base, run(m, sym))
          checked = checked + 1
        end
      end
    end
  end
  ::continue::
end
D.check("записей с кириллической формой больше 150", true, total > 150)
io.stdout:write(("записей %d, сравнений %d\n"):format(total, checked))

-- 2. Сценарии приёмки insert (сообщение главной сессии): Ctrl+ц удаляет слово, а не
-- печатает «ц»; Alt-формы — как латинские.
local function case(name, keys, expect, lines, cur, check)
  reset(lines, cur)
  D.input(keys)
  D.sync()
  D.row(name, keys, expect, check())
end
local function lines()
  return D.lines()
end
case("i <C-ц> удаляет слово", "A<C-ц><Esc>", { "one " }, { "one two" }, { 1, 0 }, lines)
case("i <C-г> удаляет до начала", "A<C-г><Esc>", { "" }, { "one two" }, { 1, 0 }, lines)
case("i <C-р> удаляет символ", "A<C-р><Esc>", { "one tw" }, { "one two" }, { 1, 0 }, lines)
case("i <C-к>ф вставляет регистр a", "o<C-к>ф<Esc>", { "x", "REG" }, { "x" }, { 1, 0 }, lines)
case("i <C-к><C-к>ф", "o<C-к><C-к>ф<Esc>", { "x", "REG" }, { "x" }, { 1, 0 }, lines)
case("i <C-щ>вв — dd из insert", "A<C-щ>вв<Esc>", { "x" }, { "one", "x" }, { 1, 0 }, lines)
case(
  "i <C-ч><C-т> — дополнение",
  "A<C-ч><C-т><Esc>",
  { "alpha", "alpha" },
  { "alpha", "al" },
  { 2, 1 },
  lines
)
case(
  "i <C-т>, <C-з> — дополнение",
  "A<C-т><C-з><Esc>",
  { "alpha", "al" },
  { "alpha", "al" },
  { 2, 1 },
  lines
)
case("i <C-е> — отступ", "A<C-е><Esc>", { "\tx" }, { "x" }, { 1, 0 }, lines)
case("i <C-м><C-в> — буквально ^D", "i<C-м><C-в><Esc>", { "\4x" }, { "x" }, { 1, 0 }, lines)
case("i <C-й><C-в> — буквально ^D", "i<C-й><C-в><Esc>", { "\4x" }, { "x" }, { 1, 0 }, lines)
case("i <C-м>в — кириллица буквально", "i<C-м>в<Esc>", { "вx" }, { "x" }, { 1, 0 }, lines)
case("i <C-п>г — точка разрыва отмены", "A1<C-п>г2<Esc>u", { "ab1" }, { "ab" }, { 1, 0 }, lines)
case("i <C-g>г — то же с латинским Ctrl", "A1<C-g>г2<Esc>u", { "ab1" }, { "ab" }, { 1, 0 }, lines)
case("i <C-\\><C-т> — в normal", "i<C-\\><C-т>", "n", { "x" }, { 1, 0 }, function()
  return D.lua("return vim.fn.mode(1)")
end)
case("i <M-в> = <M-d>", "A<M-в>", "no", { "a b" }, { 1, 0 }, function()
  return D.lua("return vim.fn.mode(1)")
end)
case(
  "c <C-r>ф — регистр по физической клавише",
  ":<C-r>ф",
  "REG",
  { "x" },
  { 1, 0 },
  function()
    return D.lua("return vim.fn.getcmdline()")
  end
)
case(
  "c <C-к><C-ц> — слово под курсором",
  ":<C-к><C-ц>",
  "alpha",
  { "alpha beta" },
  { 1, 0 },
  function()
    return D.lua("return vim.fn.getcmdline()")
  end
)
case("c <C-r><C-ц> — смешанная форма", ":<C-r><C-ц>", "alpha", { "alpha beta" }, { 1, 0 }, function()
  return D.lua("return vim.fn.getcmdline()")
end)
case("c <C-\\>у — выражение", ":abc<C-\\>у'zz'<CR>", "zz", { "x" }, { 1, 0 }, function()
  return D.lua("return vim.fn.getcmdline()")
end)
case("n <S-В> = D", "<S-В>", { "" }, { "abc" }, { 1, 0 }, lines)
case("i <S-В> — текст В", "i<S-В><Esc>", { "Вx" }, { "x" }, { 1, 0 }, lines)
case("x п<C-ф> = g<C-a>", "VGп<C-ф>", { "2", "3" }, { "1", "1" }, { 1, 0 }, lines)

-- 3. Приоритеты: алиас ниже дубля и чужой привязки; снятие возвращает алиас.
local function maparg(lhs, mode)
  return D.lua("return vim.fn.maparg(...)", lhs, mode)
end
local function hits()
  return D.lua("return _G.HITS")
end
D.lua([[_G.HITS = {}
  _G.hit = function(n) return function() HITS[n] = (HITS[n] or 0) + 1 end end]])
D.check("алиас n <C-в>", "<C-D>", maparg("<C-в>", "n"))
D.lua([[vim.keymap.set("n", "<C-d>", hit("d"))]])
reset({ "x" }, { 1, 0 })
D.input("<C-в>")
D.sync()
D.check(
  "<C-в> → привязка пользователя <C-d> (дубль поверх алиаса)",
  { d = 1 },
  hits()
)
D.lua([[vim.keymap.del("n", "<C-d>")]])
D.check("после снятия <C-d> алиас <C-в> снова на месте", "<C-D>", maparg("<C-в>", "n"))
D.check("x <C-в> не тронут", "<C-D>", maparg("<C-в>", "x"))

D.lua([[_G.HITS = {}; vim.keymap.set("n", "<C-ы>", hit("cyr"))]])
reset({ "x" }, { 1, 0 })
D.input("<C-ы><C-s>")
D.sync()
D.check("чужая <C-ы>: срабатывает и по <C-s> (обратный дубль)", { cyr = 2 }, hits())
D.lua([[vim.keymap.del("n", "<C-ы>")]])
D.check("после снятия <C-ы> — алиас", "<C-S>", maparg("<C-ы>", "n"))
D.check("после снятия <C-ы> обратный дубль снят", "", maparg("<C-s>", "n"))

-- Латинская привязка на месте обратного дубля главнее.
D.lua([[_G.HITS = {}; vim.keymap.set("n", "<C-e>", hit("lat")); vim.keymap.set("n", "<C-у>", hit("cyr"))]])
reset({ "x" }, { 1, 0 })
D.input("<C-e><C-у>")
D.sync()
D.check(
  "<C-e> пользователя не перекрыт обратным дублем <C-у>",
  { lat = 1, cyr = 1 },
  hits()
)

-- Две формы дубля: <C-w>x → <C-ц>ч и <C-w>ч.
D.lua([[_G.HITS = {}; vim.keymap.set("n", "<C-w>x", hit("wx"))]])
for _, k in ipairs({ "<C-w>x", "<C-ц>ч", "<C-w>ч" }) do
  reset({ "x" }, { 1, 0 })
  D.input(k)
  D.sync()
end
D.check("<C-w>x, <C-ц>ч, <C-w>ч — одна привязка", { wx = 3 }, hits())

-- Чужая кириллическая с буквой: <C-ц>я → обратный <C-w>я.
D.lua([[_G.HITS = {}; vim.keymap.set("n", "<C-ц>я", hit("wz"))]])
for _, k in ipairs({ "<C-ц>я", "<C-w>я" }) do
  reset({ "x" }, { 1, 0 })
  D.input(k)
  D.sync()
end
D.check("<C-ц>я и <C-w>я — одна привязка", { wz = 2 }, hits())

-- Повторный setup() не меняет алиасов и не даёт ошибок.
D.check("setup() повторно без ошибок", true, D.lua([[return pcall(require("ru-layout").setup)]]))
D.check("алиас после повторного setup", "<C-D>", maparg("<C-в>", "n"))

-- 4. Терминальный буфер: <C-ф> и <M-в> доходят до программы как <C-a> и <M-d>.
D.lua([[vim.cmd("enew! | terminal cat -v")]])
D.input("i")
D.sync()
local function term_line(keys, want)
  D.input(keys .. "<CR>")
  D.lua(
    [[local want = ...
    vim.wait(2 ^ 31 - 1, function()
      return vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), want)
    end, 5)]],
    want
  )
  return want
end
-- ^D линия терминала поглощает (конец файла), поэтому проверяется ^N.
D.check("t <C-ф><C-т>", "^A^N", term_line("<C-ф><C-т>", "^A^N"))
D.check("t <M-в>", "^[d", term_line("<M-в>", "^[d"))
D.input("<C-\\><C-т>")
D.check("t <C-\\><C-т> — в normal", "nt", D.sync())

-- 5. getchar()/getcharstr(): сочетание с модификатором — латинская форма.
reset({ "x" }, { 1, 0 })
local gc = D.lua([[
  local r = {}
  for _, k in ipairs({ "<C-в>", "<M-в>", "<C-S-В>", "в", "<C-d>" }) do
    vim.api.nvim_feedkeys(vim.keycode(k), "t", false)
    local a = vim.fn.getchar()
    vim.api.nvim_feedkeys(vim.keycode(k), "t", false)
    local b = vim.fn.getcharstr()
    r[#r + 1] = { k, type(a) == "string" and vim.fn.keytrans(a) or a, vim.fn.keytrans(b) }
  end
  return r]])
D.check("getchar/getcharstr", {
  { "<C-в>", 4, "<C-D>" },
  { "<M-в>", "<M-d>", "<M-d>" },
  { "<C-S-В>", "<C-S-D>", "<C-S-D>" },
  { "в", 1074, "в" },
  { "<C-d>", 4, "<C-D>" },
}, gc)

-- Чтение клавиши плагином в привязке (как mini.surround и which-key): <C-в> → <C-d>.
D.lua([[vim.keymap.set("n", "Q", function() _G.GOT = vim.fn.keytrans(vim.fn.getcharstr()) end)]])
reset({ "x" }, { 1, 0 })
D.input("Q<C-в>")
D.sync()
D.check("getcharstr в привязке: <C-в> → <C-d>", "<C-D>", D.lua("return _G.GOT"))

D.stop()
D.finish()
