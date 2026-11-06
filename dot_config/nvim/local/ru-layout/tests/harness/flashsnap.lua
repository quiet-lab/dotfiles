-- Снимок состояния flash в испытуемом nvim: состояние прыжка и метки (из extmarks).
local M = {}
local function line_word(buf, row, col)
  local l = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local s = l:sub(col + 1)
  return s:match("^[%w\128-\255]+") or s:sub(1, 6)
end
function M.marks(buf)
  buf = buf or 0
  local ns = vim.api.nvim_get_namespaces().flash
  if not ns then
    return {}
  end
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_text then
      local t = table.concat(vim.tbl_map(function(c)
        return c[1]
      end, d.virt_text))
      out[#out + 1] = { label = t, row = m[2] + 1, col = m[3], word = line_word(buf, m[2], m[3]) }
    end
  end
  table.sort(out, function(a, b)
    return a.row == b.row and a.col < b.col or a.row < b.row
  end)
  return out
end
function M.state(kind)
  local st
  if kind == "char" then
    st = require("flash.plugins.char").state
  else
    st = require("flash.repeat")._states[kind or "jump"]
  end
  if not st then
    return { exists = false }
  end
  local labeled = {}
  for _, m in ipairs(st.results) do
    if m.label then
      labeled[#labeled + 1] = {
        label = m.label,
        row = m.pos[1],
        col = m.pos[2],
        word = line_word(vim.api.nvim_win_get_buf(m.win), m.pos[1] - 1, m.pos[2]),
      }
    end
  end
  table.sort(labeled, function(a, b)
    return a.row == b.row and a.col < b.col or a.row < b.row
  end)
  return {
    exists = true,
    visible = st.visible,
    labeled = labeled,
    pattern = st.pattern(),
    search = st.pattern.search,
    nresults = #st.results,
    labels = table.concat(
      vim.tbl_map(function(l)
        return l
      end, st:labels()),
      ""
    ),
  }
end
function M.snap(kind)
  local s = M.state(kind)
  s.marks = M.marks()
  s.mode = vim.fn.mode(1)
  s.cursor = vim.api.nvim_win_get_cursor(0)
  s.word_at_cursor = line_word(0, s.cursor[1] - 1, s.cursor[2])
  return s
end
-- Краткая строка меток: "a:привет@3:5 ..."
function M.brief(snap, n)
  local t = {}
  local list = snap.labeled or {}
  for i, m in ipairs(list) do
    if i > (n or 12) then
      t[#t + 1] = "…(" .. #list .. ")"
      break
    end
    t[#t + 1] = ("%s:%s@%d:%d"):format(m.label, m.word, m.row, m.col)
  end
  return table.concat(t, " ")
end
return M
