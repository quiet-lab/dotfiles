-- Раскладка из Hyprland: ru-layout.layout на двойнике fake-hypr.py.
-- Запуск: cd <корень плагина> && nvim -l tests/layout_spec.lua
-- Воспроизводит опыты 3, 4, 7, 8 прототипа: switch_to, внешнее переключение,
-- обрыв и переподключение по inotify, работа без Hyprland. Все ожидания —
-- vim.wait с условием по состоянию модуля (до события), без сроков.
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

-- Верхний предел vim.wait: ожидание идёт до события, зависание ловит предел прогона.
local FOREVER = 2 ^ 31 - 1

local function eq(name, expect, fact)
  D.row(name, "", expect, fact)
end

-- Ожидание в испытуемом nvim, пока get() не станет равным code (nil — "nil").
local function wait_code(code)
  return D.lua(
    [[local code = ...
    local L = require("ru-layout.layout")
    vim.wait(2 ^ 31 - 1, function() return tostring(L.get()) == code end, 1)
    return tostring(L.get())]],
    tostring(code)
  )
end

-- Запись событий User LayoutChanged испытуемого в _G.layout_events.
local RECORD = [[
_G.layout_events = {}
vim.api.nvim_create_autocmd("User", { pattern = "LayoutChanged", callback = function(ev)
  table.insert(_G.layout_events, { old = tostring(ev.data.old), new = tostring(ev.data.new) })
end })
]]

local function events()
  return D.lua("local e = _G.layout_events; _G.layout_events = {}; return e")
end

local function state()
  return D.lua([[local S = require("ru-layout.layout")._state()
    return { requests = S.requests, watchers = #S.watchers, ev = tostring(S.ev) }]])
end

-- Раскладка двойника по запросу j/devices.
local function hypr_keymap()
  return vim.json.decode(D.hypr_request("j/devices")).keyboards[1].active_keymap
end

-- Второй двойник с другой подписью в том же $XDG_RUNTIME_DIR испытуемого.
-- В drv.lua нет метода перезапуска двойника, поэтому он поднимается здесь.
local extra_job
local function start_extra(rt, sig, keymap)
  local out = {}
  extra_job = vim.fn.jobstart({ "python3", "-I", here .. "/harness/fake-hypr.py", rt .. "/hypr", sig, keymap }, {
    on_stdout = function(_, data)
      vim.list_extend(out, data)
    end,
  })
  assert(extra_job > 0, "второй двойник не запустился")
  vim.wait(FOREVER, function()
    return vim.tbl_contains(out, "ready")
  end, 1)
end
local function stop_extra()
  if extra_job then
    vim.fn.jobstop(extra_job)
    vim.fn.jobwait({ extra_job }, FOREVER)
    extra_job = nil
  end
end

local ok, err = pcall(function()
  -- (а) запуск при ru.
  D.start({ hypr = "ru" })
  D.lua(RECORD)
  eq("а: setup() при Hyprland", true, D.lua("return require('ru-layout.layout').setup()"))
  eq("а: get() после подключения", "ru", wait_code("ru"))
  eq("а: событие подключения", { { old = "nil", new = "ru" } }, events())

  -- Повторный setup() не плодит подписок и наблюдателей.
  local before = state()
  eq("а: повторный setup()", true, D.lua("return require('ru-layout.layout').setup()"))
  eq(
    "а: повторный setup() — та же труба, без запросов и наблюдателей",
    before,
    state()
  )

  -- (б) switch_to("us").
  eq(
    "б: switch_to('us')",
    true,
    D.lua([[_G.sw_reply = nil
      return require('ru-layout.layout').switch_to("us", function(ok) _G.sw_reply = ok end)]])
  )
  eq("б: get() после события", "us", wait_code("us"))
  eq(
    "б: ответ сокета ok",
    true,
    D.lua("vim.wait(2 ^ 31 - 1, function() return _G.sw_reply ~= nil end, 1); return _G.sw_reply")
  )
  eq("б: двойник в us", "English (US)", hypr_keymap())
  eq("б: событие old=ru new=us", { { old = "ru", new = "us" } }, events())
  local req = state().requests
  eq("б: повторный switch_to('us')", true, D.lua("return require('ru-layout.layout').switch_to('us')"))
  eq("б: повторный switch_to без запроса", req, state().requests)
  eq("б: неизвестный код", false, D.lua("return require('ru-layout.layout').switch_to('de')"))

  -- (в) внешнее переключение.
  D.hypr_switch("ru")
  eq(
    "в: get() после внешнего переключения",
    "ru",
    D.lua("return require('ru-layout.layout').get()")
  )
  eq("в: событие old=us new=ru", { { old = "us", new = "ru" } }, events())

  -- (е) событие другого устройства не меняет состояние.
  D.lua("require('ru-layout.layout')._feed(...)", "activelayout>>hl-virtual-keyboard-wtype,English (US)")
  eq("е: чужое устройство — get()", "ru", D.lua("return require('ru-layout.layout').get()"))
  eq("е: чужое устройство — без события", {}, events())

  -- (г) обрыв: двойник остановлен, затем новый с другой подписью.
  vim.uv.kill(D.hypr_pid, "sigterm")
  eq("г: get() после обрыва", "nil", wait_code(nil))
  eq("г: событие old=ru new=nil", { { old = "ru", new = "nil" } }, events())
  eq("г: switch_to без Hyprland", false, D.lua("return require('ru-layout.layout').switch_to('us')"))
  eq(
    "г: ожидание экземпляра по inotify",
    true,
    D.lua("return require('ru-layout.layout').info().waiting")
  )
  local rt = D.lua("return vim.env.XDG_RUNTIME_DIR")
  start_extra(rt, "test2", "English (US)")
  eq("г: get() нового экземпляра", "us", wait_code("us"))
  eq(
    "г: подключён к test2",
    "test2",
    D.lua("return vim.fn.fnamemodify(require('ru-layout.layout').info().base, ':t')")
  )
  eq("г: наблюдатели сняты", 0, state().watchers)
  eq(
    "г: switch_to('ru') на новом экземпляре",
    true,
    D.lua("return require('ru-layout.layout').switch_to('ru')")
  )
  eq("г: get() после switch_to", "ru", wait_code("ru"))
  stop_extra()
  eq("г: get() после второго обрыва", "nil", wait_code(nil))
  D.stop()

  -- (д) без Hyprland: пустой $XDG_RUNTIME_DIR, каталога hypr нет.
  D.start({})
  D.lua(RECORD)
  eq("д: setup() без Hyprland", { true, false }, D.lua("return { pcall(require('ru-layout.layout').setup) }"))
  eq("д: get()", "nil", D.lua("return tostring(require('ru-layout.layout').get())"))
  eq("д: switch_to", false, D.lua("return require('ru-layout.layout').switch_to('us')"))
  eq("д: повторный setup()", false, D.lua("return require('ru-layout.layout').setup()"))
  eq("д: один наблюдатель ($XDG_RUNTIME_DIR)", 1, state().watchers)
  eq("д: :messages пусто", "", vim.trim(D.lua("return vim.fn.execute('messages')")))
  -- Появление каталога hypr и экземпляра: подключение по inotify.
  start_extra(D.lua("return vim.env.XDG_RUNTIME_DIR"), "late", "Russian")
  eq("д: подключение к появившемуся экземпляру", "ru", wait_code("ru"))
  eq("д: событие подключения", { { old = "nil", new = "ru" } }, events())
  stop_extra()
  eq("д: get() после остановки", "nil", wait_code(nil))
  eq("д: :messages пусто в конце", "", vim.trim(D.lua("return vim.fn.execute('messages')")))
end)
if not ok then
  D.row("исключение", "", "нет", tostring(err), false)
end
stop_extra()
D.stop()
D.finish()
