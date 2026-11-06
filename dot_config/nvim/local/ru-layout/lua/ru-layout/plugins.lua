-- Обёртки плагинов, которые сами читают клавиши (`getchar()`, `getcharstr()`): на время
-- такого чтения кириллица переводится в латиницу той же физической клавиши
-- (`ru-layout.getchar`). Обёртка ставится по загрузке плагина: lazy.nvim шлёт
-- `User LazyLoad` с именем плагина, уже загруженные обрабатывает `setup()`.
--
-- `M.consumers` — обёрнутые плагины, `M.ignored` — известные плагины, которым обёртка
-- не нужна. У каждого записано, сколько строк с чтением клавиш в каком файле
-- (`points`, путь от каталога плагина): сторожевой тест `tests/guard_spec.lua` ищет
-- такие строки в `~/.local/share/nvim/lazy` и падает на новом плагине, новом файле
-- или изменившемся числе строк. Число по файлу, а не номера строк: номера сдвигает
-- любая правка плагина, а число меняется только с появлением или исчезновением точки
-- чтения.
local G = require("ru-layout.getchar")
local tr = require("ru-layout.tr")

local M = {}

-- Шаблон поиска точек чтения клавиш (ripgrep). Строки-комментарии не считаются.
M.pattern = [[fn\.getchar(str)?\b|\bgetchar(str)?\s*\(]]

local api = vim.api
local augroup

-- Есть ли в строке кириллическая буква раскладки ЙЦУКЕН.
local function has_cyrillic(s)
  for _, c in ipairs(vim.fn.split(s, "\\zs")) do
    if tr.ru2us[c] then
      return true
    end
  end
  return false
end
M.has_cyrillic = has_cyrillic

-- Привязка, которую окно which-key не показывает: lhs с кириллицей. Это дубли
-- модуля `keymap` (`<leader>аа` рядом с `<leader>ff`); после перевода клавиш в
-- `which-key.state.getchar` окно ведёт только латинское дерево.
function M.wk_hidden(keymap)
  return type(keymap) == "table" and type(keymap.lhs) == "string" and has_cyrillic(keymap.lhs)
end

local patched = setmetatable({}, { __mode = "k" })

-- which-key: перевод клавиш, которые окно читает само (`state.getchar`), и скрытие
-- кириллических дублей. Дубли отсекаются на входе в дерево (`Tree:add`), а не опцией
-- `filter`: опции which-key пересобирает при отложенной загрузке, а метод дерева
-- действует при любом порядке настройки. Дерево уже открытых буферов пересобирается.
local function apply_which_key()
  local st = require("which-key.state")
  assert(G.wrap(st, "getchar"), "which-key.state.getchar не найдена")
  local Tree = require("which-key.tree")
  if not patched[Tree] then
    local add = assert(Tree.add, "which-key.tree.add не найдена")
    Tree.add = function(self, keymap, ...)
      if M.wk_hidden(keymap) then
        return
      end
      return add(self, keymap, ...)
    end
    patched[Tree] = add
  end
  -- rawget: обращение к полю через метатаблицу настроило бы which-key заново.
  local Config = require("which-key.config")
  if rawget(Config, "loaded") then
    require("which-key.buf").clear()
  end
end

-- mini.ai: обработчики `a`/`i` и их вариантов читают идентификатор объекта внутри
-- expr-привязки, а сами функции лежат в локальной таблице плагина. Поэтому
-- кириллические привязки (`ш`, `ф`, `шт`, `пх` …) ставятся заново с переводом вокруг
-- того же обработчика; латинские остаются как есть.
local MINIAI_MAPS = {
  around = { "x", "o" },
  inside = { "x", "o" },
  around_next = { "x", "o" },
  inside_next = { "x", "o" },
  around_last = { "x", "o" },
  inside_last = { "x", "o" },
  goto_left = { "n", "x", "o" },
  goto_right = { "n", "x", "o" },
}
local function apply_mini_ai()
  local cfg = assert(_G.MiniAi and MiniAi.config, "MiniAi не настроен")
  for field, modes in pairs(MINIAI_MAPS) do
    local lhs = cfg.mappings[field]
    if type(lhs) == "string" and lhs ~= "" then
      local ru = tr.lhs_to_ru(lhs)
      if ru ~= lhs then
        for _, mode in ipairs(modes) do
          local d = vim.fn.maparg(lhs, mode, false, true)
          if d.callback then
            vim.keymap.set(mode, ru, G.wrap_fn(d.callback), {
              expr = d.expr == 1,
              remap = d.noremap == 0,
              silent = d.silent == 1,
              nowait = d.nowait == 1,
              desc = d.desc,
            })
          end
        end
      end
    end
  end
end

-- mini.surround: функции таблицы MiniSurround вызываются из привязок через
-- `operatorfunc` и `<Cmd>lua MiniSurround.…()` при каждом нажатии, поэтому их
-- достаточно заменить обёртками. find_left отдельной функции не имеет.
local MINISURROUND_FNS = { "add", "delete", "replace", "find", "find_left", "highlight", "update_n_lines" }
local function apply_mini_surround()
  assert(_G.MiniSurround, "MiniSurround не настроен")
  for _, name in ipairs(MINISURROUND_FNS) do
    G.wrap(MiniSurround, name)
  end
end

-- mini.files: закладки `m`/`'` — локальные функции, привязанные к буферу проводника.
-- По событию `MiniFilesBufferCreate` (после привязок) их обработчики ставятся заново
-- с переводом — и латинские, и кириллические (`ь`, `э`).
local function wrap_minifiles_buf(buf)
  local cfg = _G.MiniFiles and MiniFiles.config
  if not (cfg and api.nvim_buf_is_valid(buf)) then
    return
  end
  for _, field in ipairs({ "mark_goto", "mark_set" }) do
    local lhs = cfg.mappings[field]
    if type(lhs) == "string" and lhs ~= "" then
      local d
      api.nvim_buf_call(buf, function()
        d = vim.fn.maparg(lhs, "n", false, true)
      end)
      if d.buffer == 1 and d.callback and not G.is_wrapped(d.callback) then
        local w = G.wrap_fn(d.callback)
        local o = { buffer = buf, desc = d.desc, nowait = true }
        vim.keymap.set("n", lhs, w, o)
        local ru = tr.lhs_to_ru(lhs)
        if ru ~= lhs then
          vim.keymap.set("n", ru, w, o)
        end
      end
    end
  end
end
M.wrap_minifiles_buf = wrap_minifiles_buf

local function apply_mini_files()
  local g = api.nvim_create_augroup("ru-layout.plugins.mini.files", { clear = true })
  api.nvim_create_autocmd("User", {
    group = g,
    pattern = "MiniFilesBufferCreate",
    desc = "ru-layout: перевод клавиш закладок mini.files",
    callback = function(args)
      wrap_minifiles_buf(args.data and args.data.buf_id or args.buf)
    end,
  })
end

-- neogit: в меню (popup) префикс аргумента (`-`, `=`) читает следующую букву
-- `getcharstr()` в замыкании, которое строит `Popup:mappings()`. Обёртка метода
-- оборачивает в таблице привязок обработчики клавиш-префиксов.
local function apply_neogit()
  local P = require("neogit.lib.popup")
  if patched[P] then
    return
  end
  local mappings = assert(P.mappings, "neogit.lib.popup.mappings не найдена")
  P.mappings = function(self, ...)
    local m = mappings(self, ...)
    local n = m and m.n
    if type(n) == "table" then
      for k, v in pairs(n) do
        if type(k) == "string" and type(v) == "function" then
          for kk in pairs(n) do
            if type(kk) == "string" and #kk > #k and kk:sub(1, #k) == k then
              n[k] = G.wrap_fn(v)
              break
            end
          end
        end
      end
    end
    return m
  end
  patched[P] = mappings
end

-- Плагины-потребители: модуль, по которому видно загрузку без lazy.nvim, функция
-- установки, точки чтения клавиш и способ.
M.consumers = {
  ["which-key.nvim"] = {
    module = "which-key",
    apply = apply_which_key,
    points = { ["lua/which-key/state.lua"] = 4 },
    how = "which-key.state.getchar — обёртка; Tree:add — без кириллических дублей",
  },
  ["mini.ai"] = {
    module = "mini.ai",
    apply = apply_mini_ai,
    points = { ["lua/mini/ai.lua"] = 1 },
    how = "кириллические привязки a/i/an/in/al/il/g[/g] — обработчик с переводом",
  },
  ["mini.surround"] = {
    module = "mini.surround",
    apply = apply_mini_surround,
    points = { ["lua/mini/surround.lua"] = 1 },
    how = "MiniSurround.add/delete/replace/find/highlight/update_n_lines — обёртки",
  },
  ["mini.files"] = {
    module = "mini.files",
    apply = apply_mini_files,
    points = { ["lua/mini/files.lua"] = 3 },
    how = "закладки m/' буфера проводника — по MiniFilesBufferCreate",
  },
  ["snacks.nvim"] = {
    module = "snacks",
    apply = function()
      assert(G.wrap(require("snacks.picker.util"), "pick_win"), "snacks.picker.util.pick_win не найдена")
    end,
    points = { ["lua/snacks/picker/util/init.lua"] = 1 },
    how = "snacks.picker.util.pick_win — обёртка",
  },
  ["bufferline.nvim"] = {
    module = "bufferline",
    apply = function()
      assert(G.wrap(require("bufferline.pick"), "choose_then"), "bufferline.pick.choose_then не найдена")
    end,
    points = { ["lua/bufferline/pick.lua"] = 1 },
    how = "bufferline.pick.choose_then — обёртка",
  },
  ["neogit"] = {
    module = "neogit",
    apply = apply_neogit,
    points = { ["lua/neogit/lib/popup/init.lua"] = 1 },
    how = "Popup:mappings — обработчики префиксов аргументов с переводом",
  },
  ["neotest"] = {
    module = "neotest",
    apply = function()
      assert(G.wrap(require("neotest.lib.ui"), "open_buf"), "neotest.lib.ui.open_buf не найдена")
    end,
    points = { ["lua/neotest/lib/ui/init.lua"] = 1 },
    how = "neotest.lib.ui.open_buf (выбор окна внутри, select_win локальная) — обёртка",
  },
  ["nvim-dap-ui"] = {
    module = "dapui",
    apply = function()
      assert(G.wrap(require("dapui.util"), "select_win"), "dapui.util.select_win не найдена")
    end,
    points = { ["lua/dapui/util.lua"] = 1 },
    how = "dapui.util.select_win — обёртка",
  },
  ["diffview.nvim"] = {
    module = "diffview",
    apply = function()
      assert(G.wrap(require("diffview.utils"), "input_char"), "diffview.utils.input_char не найдена")
    end,
    points = { ["lua/diffview/utils.lua"] = 2 },
    how = "diffview.utils.input_char — обёртка (сейчас только «нажмите любую клавишу»)",
  },
}

-- Известные плагины с чтением клавиш, которым обёртка не нужна.
M.ignored = {
  ["flash.nvim"] = {
    points = { ["lua/flash/util.lua"] = 1 },
    reason = "метки и поиск по обеим раскладкам ведёт модуль ru-layout.flash",
  },
  ["vim-fugitive"] = {
    points = { ["autoload/fugitive.vim"] = 2 },
    reason = "getchar(1) и getchar() — только прерывание фонового задания (<C-d>, <Esc>)",
  },
  ["lazy.nvim"] = {
    points = { ["bootstrap.lua"] = 1 },
    reason = "«нажмите любую клавишу» после ошибки установки",
  },
  ["LazyVim"] = {
    points = { ["init.lua"] = 1, ["lua/lazyvim/plugins/init.lua"] = 1 },
    reason = "«нажмите любую клавишу» при старой версии Neovim",
  },
}

M.status = {}

-- Установка обёртки одного плагина (без проверки загрузки). Ошибка не прерывает
-- запуск: сообщение уходит в vim.notify, итог — в M.status[name].
function M.apply(name)
  local c = M.consumers[name]
  if not c then
    return false
  end
  local ok, err = pcall(c.apply)
  M.status[name] = ok or err
  if not ok then
    vim.notify(("ru-layout: обёртка %s не установлена: %s"):format(name, err), vim.log.levels.WARN)
  end
  return ok
end

-- Загружен ли плагин: по lazy.nvim, без него — по загруженному модулю.
function M.is_loaded(name)
  local ok, cfg = pcall(require, "lazy.core.config")
  if ok and type(cfg.plugins) == "table" and cfg.plugins[name] then
    return cfg.plugins[name]._.loaded ~= nil
  end
  local c = M.consumers[name]
  return c ~= nil and package.loaded[c.module] ~= nil
end

-- Обёртки для уже загруженных плагинов и подписка на загрузку остальных.
-- Повторный вызов подписку не удваивает.
function M.setup()
  augroup = api.nvim_create_augroup("ru-layout.plugins", { clear = true })
  api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "LazyLoad",
    desc = "ru-layout: обёртки плагинов, читающих клавиши",
    callback = function(args)
      if M.consumers[args.data] then
        M.apply(args.data)
      end
    end,
  })
  for name in pairs(M.consumers) do
    if M.is_loaded(name) then
      M.apply(name)
    end
  end
end

return M
