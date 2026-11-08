# Поставщик контекста ble.sh для плагина herdr keys-help.
#
# Пишет запись канала (решение D2 изменения herdr-keys-help)
# $XDG_RUNTIME_DIR/herdr-keys-help/panes/$HERDR_PANE_ID/ble-$$.json:
# текущий keymap ble.sh (state = active), запуск команды из строки
# (state = exec) и выполнение привязки -x/-c (state = widget). Рядом,
# в $XDG_RUNTIME_DIR/herdr-keys-help/ble/$$/, лежат дампы `ble-bind -P`
# по одному на keymap; путь дампа — поле table записи.
#
# Запись делает встроенный printf, смена keymap внешних процессов
# не запускает. Внешние mkdir и rm запускаются только при первой
# записи (создание каталогов) и при выходе оболочки (уборка).
#
# Вне herdr (нет HERDR_PANE_ID или XDG_RUNTIME_DIR) модуль ничего
# не делает. Подключается из ~/.blerc.

[[ ${HERDR_PANE_ID-} && ${XDG_RUNTIME_DIR-} && ${BLE_VERSION-} ]] || return 0

_keys_help_base=$XDG_RUNTIME_DIR/herdr-keys-help
_keys_help_pane_dir=$_keys_help_base/panes/$HERDR_PANE_ID
_keys_help_record=$_keys_help_pane_dir/ble-$$.json
_keys_help_dump_dir=$_keys_help_base/ble/$$
_keys_help_env_file=$_keys_help_base/env-vars
_keys_help_env_mark=$_keys_help_dump_dir/env-vars.read
# Последняя записанная пара «состояние режим команда»: запись только
# при её изменении.
_keys_help_last=
# Идёт запись (защита от повторного входа из дампа).
_keys_help_busy=
# Каталоги созданы в этой оболочке.
_keys_help_ready=
# Keymap, для которых дамп уже записан.
declare -gA _keys_help_dumped=()
# Имена переменных окружения для поля env (файл env-vars просмотрщика).
_keys_help_env_names=()
_keys_help_env_json='{}'

# Строка $1 в виде строки JSON (в кавычках) в переменную ret.
function keys_help/json-string {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  if [[ $s == *[$'\x01'-$'\x1f\x7f']* ]]; then
    # Прочие управляющие символы — через \uXXXX, посимвольно.
    local out= c i code
    for ((i = 0; i < ${#s}; i++)); do
      c=${s:i:1}
      if [[ $c == [$'\x01'-$'\x1f\x7f'] ]]; then
        printf -v code '%d' "'$c"
        printf -v c '\\u%04x' "$code"
      fi
      out+=$c
    done
    s=$out
  fi
  ret=\"$s\"
}

# Создание каталогов записи и дампов: один раз на оболочку и повторно,
# если каталог панели исчез.
function keys_help/ensure-dirs {
  [[ $_keys_help_ready && -d $_keys_help_pane_dir && -d $_keys_help_dump_dir ]] && return 0
  command mkdir -p -- "$_keys_help_pane_dir" "$_keys_help_dump_dir" 2>/dev/null || return 1
  _keys_help_ready=1
}

# Перечитывание имён переменных для поля env, если файл просмотрщика
# новее прочитанного. Без внешних процессов.
function keys_help/read-env-names {
  [[ -f $_keys_help_env_file ]] || return 0
  [[ -e $_keys_help_env_mark && ! $_keys_help_env_file -nt $_keys_help_env_mark ]] && return 0
  local -a names=()
  mapfile -t names < "$_keys_help_env_file" 2>/dev/null
  _keys_help_env_names=()
  local name
  for name in "${names[@]}"; do
    [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && _keys_help_env_names+=("$name")
  done
  : > "$_keys_help_env_mark" 2>/dev/null
  keys_help/update-env-json
}

# Поле env записи из текущих значений переменных.
function keys_help/update-env-json {
  local json= name ret
  for name in "${_keys_help_env_names[@]}"; do
    [[ ${!name+set} ]] || continue
    keys_help/json-string "${!name}"
    json+=${json:+,}\"$name\":$ret
  done
  _keys_help_env_json={$json}
}

# Дамп `ble-bind -m <keymap> -P` при первой встрече keymap.
function keys_help/dump {
  local keymap=$1
  [[ ${_keys_help_dumped[$keymap]-} ]] && return 0
  ble-bind -m "$keymap" -P > "$_keys_help_dump_dir/$keymap.bind" 2>/dev/null
  _keys_help_dumped[$keymap]=1
}

# Запись канала. $1 — состояние (active, exec, widget), $2 — команда.
function keys_help/write {
  [[ $_keys_help_busy ]] && return 0
  local _keys_help_busy=1
  local state=$1 command=${2-}
  local keymap=${_ble_decode_keymap-}
  local key="$state $keymap $command"
  [[ $key == "$_keys_help_last" ]] && return 0
  keys_help/ensure-dirs || return 0

  local ret mode=null table=null cmd=null
  if [[ $keymap ]]; then
    keys_help/dump "$keymap"
    keys_help/json-string "$keymap"; mode=$ret
    keys_help/json-string "$_keys_help_dump_dir/$keymap.bind"; table=$ret
  fi
  if [[ $state != active ]]; then
    keys_help/json-string "$command"; cmd=$ret
  fi
  printf '{"v":1,"program":"ble","mode":%s,"pid":%d,"state":"%s","command":%s,"table":%s,"server":null,"env":%s}\n' \
    "$mode" "$$" "$state" "$cmd" "$table" "$_keys_help_env_json" \
    > "$_keys_help_record" 2>/dev/null || { _keys_help_ready=; return 0; }
  _keys_help_last=$key
}

# Смена keymap: запись active, только если keymap изменился.
function keys_help/notify {
  [[ $BASHPID == "$$" ]] || return 0
  keys_help/write active
}

# Сброс дампов после ручного ble-bind: следующая запись каждого keymap
# снимет дамп заново, текущий keymap — сразу.
function keys-help-refresh {
  _keys_help_dumped=()
  _keys_help_last=
  keys_help/write active
}

function keys_help/precmd {
  keys_help/read-env-names
  keys_help/update-env-json
  keys_help/write active
}

function keys_help/preexec {
  keys_help/update-env-json
  keys_help/write exec "$1"
}

function keys_help/exit {
  [[ $BASHPID == "$$" ]] || return 0
  command rm -rf -- "$_keys_help_record" "$_keys_help_dump_dir" 2>/dev/null
}

ble/function#advice after ble/decode/keymap/push 'keys_help/notify'
ble/function#advice after ble/decode/keymap/pop 'keys_help/notify'
# Индикатор режима vi пересчитывается здесь же (его выводит
# contrib/prompt-vim-mode); функция появляется с загрузкой keymap.vi.
blehook/eval-after-load keymap_vi \
  "ble/function#advice after ble/keymap:vi/update-mode-indicator 'keys_help/notify'"

# Привязки -x (.EDIT_COMMAND) и -c (.SHELL_COMMAND): запись widget
# с командой привязки до выполнения, active — после.
ble/function#advice around ble/widget/.EDIT_COMMAND '
  keys_help/update-env-json
  keys_help/write widget "${ADVICE_WORDS[1]}"
  ble/function#advice/do
  keys_help/write active'
ble/function#advice around ble/widget/.SHELL_COMMAND '
  keys_help/update-env-json
  keys_help/write widget "${ADVICE_WORDS[1]}"
  ble/function#advice/do
  keys_help/write active'

blehook PRECMD!=keys_help/precmd
blehook PREEXEC!=keys_help/preexec
blehook ATTACH!=keys_help/notify
blehook EXIT!=keys_help/exit
