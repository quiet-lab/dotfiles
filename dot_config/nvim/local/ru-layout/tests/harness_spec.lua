-- Проверка самой оснастки: двойник Hyprland, плагины, случаи, остановка.
-- Запуск: cd <корень плагина> && nvim --headless --clean -u NONE -l tests/harness_spec.lua
-- D.hypr_switch проверяет layout_spec.lua (нужен модуль ru-layout.layout).
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local D = dofile(here .. "/harness/drv.lua")

-- Двойник Hyprland: события и запросы на сокетах.
D.start({ hypr = "ru", plugins = { "flash.nvim" } })
D.lua([[
  local uv = vim.uv
  _G.EV, _G.EVBUF = {}, ""
  local base = vim.env.XDG_RUNTIME_DIR .. "/hypr/" .. vim.env.HYPRLAND_INSTANCE_SIGNATURE
  _G.PIPE = uv.new_pipe(false)
  _G.PIPE:connect(base .. "/.socket2.sock", function(err)
    assert(not err, err)
    _G.PIPE:read_start(function(_, chunk)
      if not chunk then return end
      _G.EVBUF = _G.EVBUF .. chunk
      while true do
        local line, rest = _G.EVBUF:match("^([^\n]*)\n(.*)$")
        if not line then break end
        _G.EV[#_G.EV + 1] = line
        _G.EVBUF = rest
      end
    end)
  end)
]])
-- Ожидание n-го события внутри испытуемого: до прихода события, не по сроку.
local function wait_ev(n)
  return D.lua(
    [[local n = ...
    vim.wait(2 ^ 31 - 1, function() return #_G.EV >= n end, 1)
    return _G.EV[n] ]],
    n
  )
end
local function devices()
  return vim.json.decode(D.hypr_request("j/devices"))
end
D.check("двойник: первое событие ru", "activelayout>>dh747-w-corne,Russian", wait_ev(1))
D.check("двойник: j/devices ru", 1, devices().keyboards[1].active_layout_index)
D.check("двойник: switchxkblayout ответ", "ok", D.hypr_request("switchxkblayout dh747-w-corne 0"))
D.check("двойник: событие us", "activelayout>>dh747-w-corne,English (US)", wait_ev(2))
D.check("двойник: j/devices us", 0, devices().keyboards[1].active_layout_index)
D.check("двойник: next", "ok", D.hypr_request("switchxkblayout dh747-w-corne next"))
D.check("двойник: событие после next", "activelayout>>dh747-w-corne,Russian", wait_ev(3))

-- Плагины и случаи.
D.check("plugins: flash в rtp", "table", D.lua("return type(require('flash'))"))
D.case("case: x на abc", "x", { "bc" }, D.lines, { lines = { "abc" } })
D.case("case: ru-layout.tr доступен", "", "ghbdtn", function()
  return D.lua("return require('ru-layout.tr').to_us('привет')")
end)
D.input("i")
D.check("reset: insert", "i", D.sync())
D.reset({ "a" })
D.check("reset: normal из insert", "n", D.sync())

local pid, nvim_pid = D.hypr_pid, D.pid
D.stop()
D.check("stop: nvim завершён", true, D.nvim_exit ~= -1 and D.nvim_exit ~= nil)
D.check("stop: двойник завершён", true, D.hypr_exit ~= -1 and D.hypr_exit ~= nil)
D.check("stop: kill -0 двойника отказывает", true, vim.uv.kill(pid, 0) ~= 0)
D.check("stop: kill -0 nvim отказывает", true, vim.uv.kill(nvim_pid, 0) ~= 0)
D.finish()
