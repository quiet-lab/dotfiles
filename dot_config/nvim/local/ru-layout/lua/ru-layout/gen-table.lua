-- Генератор таблицы соответствия ЙЦУКЕН ↔ QWERTY из карты XKB пользователя
-- (тот же файл, что kb_file в hyprland.lua) через libxkbcommon (LuaJIT FFI).
-- Запуск: nvim -l gen-table.lua <карта.xkb> <выход.lua> [путь-для-шапки]
-- Третий аргумент — путь к карте в источнике chezmoi (`dot_config/X11/xkb_custom`),
-- он пишется в шапку вместо абсолютного пути.
local ffi = require("ffi")
ffi.cdef([[
typedef uint32_t xkb_keycode_t; typedef uint32_t xkb_keysym_t; typedef uint32_t xkb_layout_index_t; typedef uint32_t xkb_level_index_t;
struct xkb_context; struct xkb_keymap;
struct xkb_context *xkb_context_new(int flags);
struct xkb_keymap *xkb_keymap_new_from_string(struct xkb_context *ctx, const char *s, int format, int flags);
xkb_keycode_t xkb_keymap_min_keycode(struct xkb_keymap *k); xkb_keycode_t xkb_keymap_max_keycode(struct xkb_keymap *k);
const char *xkb_keymap_key_get_name(struct xkb_keymap *k, xkb_keycode_t kc);
xkb_layout_index_t xkb_keymap_num_layouts(struct xkb_keymap *k);
const char *xkb_keymap_layout_get_name(struct xkb_keymap *k, xkb_layout_index_t i);
xkb_layout_index_t xkb_keymap_num_layouts_for_key(struct xkb_keymap *k, xkb_keycode_t kc);
int xkb_keymap_key_get_syms_by_level(struct xkb_keymap *k, xkb_keycode_t kc, xkb_layout_index_t l, xkb_level_index_t lv, const xkb_keysym_t **syms);
uint32_t xkb_keysym_to_utf32(xkb_keysym_t ks);
]])
local X = ffi.load("xkbcommon")
local path, out = arg[1], arg[2]
local label = arg[3] or path
local src = assert(io.open(path)):read("*a")
local ctx = X.xkb_context_new(0)
local km = X.xkb_keymap_new_from_string(ctx, src, 1, 0)
assert(km ~= nil, "keymap compile failed")
local nl = X.xkb_keymap_num_layouts(km)
local names = {}
for i = 0, nl - 1 do
  names[i + 1] = ffi.string(X.xkb_keymap_layout_get_name(km, i))
end
local function char(kc, layout, level)
  local syms = ffi.new("const xkb_keysym_t*[1]")
  local n = X.xkb_keymap_key_get_syms_by_level(km, kc, layout, level, syms)
  if n ~= 1 then
    return nil
  end
  local cp = X.xkb_keysym_to_utf32(syms[0][0])
  if cp < 32 or cp == 127 then
    return nil
  end
  return vim.fn.nr2char(cp)
end
local keys, ru_to_us, ru_ascii_to_us, us_to_ru, conflicts = {}, {}, {}, {}, {}
for kc = X.xkb_keymap_min_keycode(km), X.xkb_keymap_max_keycode(km) do
  local nm = X.xkb_keymap_key_get_name(km, kc)
  -- Только основной алфавитно-цифровой блок: цифровой блок (KPDL) и LSGT
  -- дали бы ложные пары для «,» и «/».
  local kn = nm ~= nil and ffi.string(nm) or ""
  local main_block = kn == "TLDE" or kn == "BKSL" or kn:match("^A[EDCB]%d%d$")
  if main_block and X.xkb_keymap_num_layouts_for_key(km, kc) >= 2 then
    for level = 0, 1 do
      local us, ru = char(kc, 0, level), char(kc, 1, level)
      if us and ru and us ~= ru and #us == 1 then
        keys[#keys + 1] = { key = ffi.string(nm), level = level + 1, us = us, ru = ru }
        us_to_ru[us] = ru
        if #ru == 1 then
          -- ASCII-знак раскладки ru: однозначен только при известной активной раскладке.
          ru_ascii_to_us[ru] = us
          conflicts[#conflicts + 1] = string.format("%s L%d: ru %q = ASCII, на us это %q", kn, level + 1, ru, us)
        else
          ru_to_us[ru] = us
        end
      end
    end
  end
end
table.sort(keys, function(a, b)
  return a.key == b.key and a.level < b.level or a.key < b.key
end)
-- langmap: только не-ASCII символы раскладки ru (кириллица, ё, №); ASCII-знаки ru
-- (. , ; : ? " / ) в langmap не входят: они совпадают с командами раскладки us.
local function esc(c)
  return (c:gsub('([,;\\"|])', "\\%1"))
end
local from, to = {}, {}
for _, k in ipairs(keys) do
  if #k.ru > 1 then
    from[#from + 1] = esc(k.ru)
    to[#to + 1] = esc(k.us)
  end
end
local langmap = table.concat(from) .. ";" .. table.concat(to)
local f = assert(io.open(out, "w"))
f:write(
  "-- Создано gen-table.lua из карты XKB "
    .. label
    .. "\n-- Раскладки: "
    .. table.concat(names, ", ")
    .. "\n-- Не править руками.\nreturn "
)
f:write(vim.inspect({
  layouts = names,
  keys = keys,
  ru_to_us = ru_to_us,
  ru_ascii_to_us = ru_ascii_to_us,
  us_to_ru = us_to_ru,
  langmap = langmap,
  ascii_conflicts = conflicts,
}))
f:write("\n")
f:close()
print(
  ("layouts=%s keys=%d langmap_pairs=%d ascii_conflicts=%d"):format(table.concat(names, ","), #keys, #from, #conflicts)
)
