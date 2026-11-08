#!/usr/bin/env bash
# Тест 6.9: поставщик контекста Neovim (keys_help.lua) в `nvim --headless`
# с временным XDG_RUNTIME_DIR и HERDR_PANE_ID. Одной командой: bash nvim_provider.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# Модуль лежит в источнике chezmoi: <корень>/dot_config/nvim/lua/keys_help.lua
root=$(cd "$here/../../../../.." && pwd)
lua_dir="$root/dot_config/nvim/lua"
[[ -f $lua_dir/keys_help.lua ]] || lua_dir="$HOME/.config/nvim/lua"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_RUNTIME_DIR=$tmp HERDR_PANE_ID="w1:p1"
nvim --headless --clean -u NONE --cmd "set rtp+=$lua_dir/.." \
  --cmd "lua package.path='$lua_dir/?.lua;'..package.path" \
  -l "$here/nvim_provider_spec.lua"
# Вне панели herdr модуль ничего не пишет.
rm -rf "$tmp/herdr-keys-help"
env -u HERDR_PANE_ID nvim --headless --clean -u NONE \
  --cmd "lua package.path='$lua_dir/?.lua;'..package.path" \
  -c 'lua require("keys_help").setup()' -c quit
[[ ! -e $tmp/herdr-keys-help ]] || { echo "FAIL: запись без HERDR_PANE_ID" >&2; exit 1; }
echo "nvim_provider: зелёный"
