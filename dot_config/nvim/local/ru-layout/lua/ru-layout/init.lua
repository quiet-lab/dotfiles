-- Точка входа «Neovim в русской раскладке». `require("ru-layout")` ничего не
-- делает: модули подключает только `setup()`. Подмена API привязок
-- (`keymap.install()`) выполняется отдельно, до lazy.setup (lua/config/lazy.lua).
local M = {}

local DEFAULTS = {
  layout = { device = "dh747-w-corne" },
  terminal = { programs = { "lazygit" } },
}

M.opts = vim.deepcopy(DEFAULTS)

-- Вызов модуля так, чтобы один упавший не валил остальные: ошибка видна в
-- сообщении уровня ERROR с именем модуля.
local function run(name, fn, ...)
  local ok, err = xpcall(fn, debug.traceback, ...)
  if not ok then
    vim.notify(("ru-layout: модуль %s: %s"):format(name, err), vim.log.levels.ERROR)
  end
  return ok
end

local function mod(name)
  return require("ru-layout." .. name)
end

-- flash ставится после его загрузки: сразу, если загружен, иначе по User LazyLoad.
local function setup_flash()
  local group = vim.api.nvim_create_augroup("ru-layout.init", { clear = true })
  if package.loaded["flash"] then
    run("flash", function()
      mod("flash").setup()
    end)
    return
  end
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    desc = "ru-layout: обёртки flash после его загрузки",
    callback = function(args)
      if args.data == "flash.nvim" then
        run("flash", function()
          mod("flash").setup()
        end)
        return true
      end
    end,
  })
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
  -- langmap задаётся, только если пуст или уже наш; чужой не затирается.
  local ours = mod("table").langmap
  if vim.o.langmap == "" or vim.o.langmap == ours then
    vim.o.langmap = ours
  end
  run("layout", function()
    mod("layout").setup(M.opts.layout)
  end)
  run("keymap", function()
    mod("keymap").sweep()
  end)
  run("punct", function()
    mod("punct").setup()
  end)
  run("macro", function()
    mod("macro").setup()
  end)
  run("rchar", function()
    mod("rchar").setup()
  end)
  run("cmdline", function()
    mod("cmdline").setup()
  end)
  run("dialogs", function()
    mod("dialogs").setup()
  end)
  run("terminal", function()
    mod("terminal").setup(M.opts.terminal)
  end)
  run("plugins", function()
    mod("plugins").setup()
  end)
  setup_flash()
end

return M
