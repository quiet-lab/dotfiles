-- Сценарий теста 6.9 (запускает nvim_provider.sh): поставщик контекста Neovim.
-- Выполняется внутри `nvim --headless`; результат — код выхода и строки FAIL в stderr.
local failures = {}
local function check(cond, msg)
  if not cond then
    failures[#failures + 1] = msg
  end
end

local dir = vim.env.XDG_RUNTIME_DIR .. "/herdr-keys-help/panes/" .. vim.env.HERDR_PANE_ID
local path = dir .. "/nvim-" .. vim.uv.os_getpid() .. ".json"

local function read()
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return vim.json.decode(text)
end

local kh = require("keys_help")
kh.setup()

local rec = read()
check(rec ~= nil, "нет записи после setup")
check(rec and rec.mode == "normal" and rec.program == "nvim" and rec.state == "active", "запись normal")
check(rec and rec.server == vim.v.servername and rec.pid == vim.uv.os_getpid(), "server и pid")

-- ModeChanged: переход в insert и обратно.
local seen = {}
local group = vim.api.nvim_create_augroup("keys_help_spec", { clear = true })
vim.api.nvim_create_autocmd("ModeChanged", {
  group = group,
  callback = function()
    local r = read()
    seen[#seen + 1] = r and r.mode or "none"
  end,
})
vim.api.nvim_feedkeys(vim.keycode("i<Esc>v<Esc>"), "x", false)
local modes = seen
check(vim.tbl_contains(modes, "insert"), "запись insert: " .. vim.inspect(modes))
check(vim.tbl_contains(modes, "visual"), "запись visual: " .. vim.inspect(modes))
check(modes[#modes] == "normal", "возврат в normal: " .. vim.inspect(modes))
check(read().mode == "normal", "финальная запись normal")

check(
  kh.mode_name("no") == "operator" and kh.mode_name("R") == "replace" and kh.mode_name("t") == "terminal",
  "mode_name"
)

-- dump: привязка с desc.
vim.keymap.set("n", "<leader>zz", "<cmd>echo 1<cr>", { desc = "Проверочная привязка" })
local list = vim.json.decode(kh.dump("n"))
local found
for _, e in ipairs(list) do
  if e.desc == "Проверочная привязка" then
    found = e
  end
end
check(found ~= nil, "dump: нет записи с desc")
check(
  found and found.rhs:lower() == "<cmd>echo 1<cr>" and found.origin ~= nil and found.group ~= nil,
  "dump: rhs, origin, group"
)
check(
  found and found.source and found.source:find("nvim_provider_spec.lua", 1, true),
  "dump: файл определения"
)

-- Выход: запись удаляется.
vim.api.nvim_exec_autocmds("VimLeavePre", {})
check(read() == nil, "запись не удалена на VimLeavePre")

if #failures > 0 then
  io.stderr:write("FAIL: " .. table.concat(failures, "\n      ") .. "\n")
  vim.cmd("cquit 1")
end
io.stdout:write("ok\n")
vim.cmd("quit")
