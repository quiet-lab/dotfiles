# Поставщик контекста ble.sh для плагина herdr keys-help.
#
# Пишет запись канала (решение D2 изменения herdr-keys-help)
# $XDG_RUNTIME_DIR/herdr-keys-help/panes/$HERDR_PANE_ID/ble-$$.json:
# текущий keymap ble.sh (state = active), запуск команды из строки
# (state = exec) и выполнение привязки -x/-c (state = widget). Рядом,
# в $XDG_RUNTIME_DIR/herdr-keys-help/ble/$$/, лежат дампы `ble-bind -P`
# по одному на keymap; путь дампа — поле table записи.
#
# Пока просмотрщик держит в каталоге панели отметку viewer.<pid> (D17),
# модуль пишет рядом с записью строку ввода ble-$$.line (курсор и текст,
# после каждой отрисовки), слова оболочки ble-$$.words (аббревиатуры,
# псевдонимы, функции; по PRECMD) и кандидаты дополнения ble-$$.cands
# (после того, как их построил ble.sh).
#
# Запись делает встроенный printf, смена keymap и нажатия внешних
# процессов не запускают. Внешние mkdir и rm запускаются только при
# первой записи (создание каталогов) и при выходе оболочки (уборка).
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
# Самая свежая отметка просмотрщика (viewer.<pid просмотрщика>),
# найденная последней проверкой.
_keys_help_mark=
_keys_help_line_file=$_keys_help_pane_dir/ble-$$.line
_keys_help_words_file=$_keys_help_pane_dir/ble-$$.words
_keys_help_cands_file=$_keys_help_pane_dir/ble-$$.cands
# Последние записанные курсор и строка, слова и кандидаты: запись
# только при изменении. Файл пишется заново и без изменения, если он
# исчез, пуст или старше самой свежей отметки (просмотрщик вернулся
# к панели или отметку поставил новый просмотрщик).
_keys_help_line_last=
_keys_help_words_last=
_keys_help_cands_last=
# Строки аббревиатур и версия _ble_complete_sabbrev_version, по которой
# они собраны.
_keys_help_sabbrev_lines=
_keys_help_sabbrev_version=
# Последняя записанная пара «состояние режим команда»: запись только
# при её изменении.
_keys_help_last=
_keys_help_last_base=
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
  keys_help/ensure-dirs || return 0
  [[ -e $_keys_help_env_mark && ! $_keys_help_env_file -nt $_keys_help_env_mark ]] && return 0
  local -a names=()
  mapfile -t names 2>/dev/null < "$_keys_help_env_file"
  _keys_help_env_names=()
  local name
  for name in "${names[@]}"; do
    [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && _keys_help_env_names+=("$name")
  done
  # 2>/dev/null — до перенаправления в файл, иначе ошибка открытия видна.
  : 2>/dev/null > "$_keys_help_env_mark"
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
  ble-bind -m "$keymap" -P 2>/dev/null > "$_keys_help_dump_dir/$keymap.bind"
  _keys_help_dumped[$keymap]=1
}

# Запись канала. $1 — состояние (active, exec, widget), $2 — команда.
function keys_help/write {
  [[ $_keys_help_busy ]] && return 0
  local _keys_help_busy=1
  local state=$1 command=${2-}
  local keymap=${_ble_decode_keymap-}
  # Keymap под вершиной стека: в auto_complete и подобных клавиши,
  # которых нет в самом keymap, через __default__ уходят ему.
  local base= n=${#_ble_decode_keymap_stack[@]}
  ((n)) && base=${_ble_decode_keymap_stack[n-1]}
  local key="$state $keymap $command"
  [[ $key == "$_keys_help_last" && $base == "$_keys_help_last_base" ]] && return 0
  keys_help/ensure-dirs || return 0

  local ret mode=null table=null cmd=null base_table=null
  if [[ $keymap ]]; then
    keys_help/dump "$keymap"
    keys_help/json-string "$keymap"; mode=$ret
    keys_help/json-string "$_keys_help_dump_dir/$keymap.bind"; table=$ret
  fi
  if [[ $base ]]; then
    keys_help/dump "$base"
    keys_help/json-string "$_keys_help_dump_dir/$base.bind"; base_table=$ret
  fi
  if [[ $state != active ]]; then
    keys_help/json-string "$command"; cmd=$ret
  fi
  printf '{"v":1,"program":"ble","mode":%s,"pid":%d,"state":"%s","command":%s,"table":%s,"base_table":%s,"server":null,"env":%s}\n' \
    "$mode" "$$" "$state" "$cmd" "$table" "$base_table" "$_keys_help_env_json" \
    2>/dev/null > "$_keys_help_record" || { _keys_help_ready=; return 0; }
  _keys_help_last=$key
  _keys_help_last_base=$base
}

# Наблюдает ли панель просмотрщик: есть ли хоть одна отметка
# viewer.*. Самая свежая — в _keys_help_mark. Встроенный
# glob, без внешних процессов; failglob пользователя на время снимается.
function keys_help/marked {
  local f newest= fg=
  [[ :$BASHOPTS: == *:failglob:* ]] && { fg=1; builtin shopt -u failglob; }
  for f in "$_keys_help_pane_dir"/viewer.*; do
    [[ -e $f ]] || continue
    [[ $newest && ! $f -nt $newest ]] || newest=$f
  done
  [[ $fg ]] && builtin shopt -s failglob
  _keys_help_mark=$newest
  [[ $newest ]]
}

# Файл $1 надо писать заново: исчез, пуст или старше отметки.
function keys_help/stale {
  [[ ! -s $1 || $_keys_help_mark -nt $1 ]]
}

# Без наблюдения изменилось то, что лежит в файле $1: файл (если он
# остался от прежнего наблюдения) обнуляется один раз, чтобы просмотрщик
# не показал устаревшее. Обнуление — встроенным перенаправлением.
function keys_help/invalidate {
  [[ -s $1 ]] && : 2>/dev/null > "$1"
}

# Значение для поля TSV: табуляции и переводы строк — пробелами.
function keys_help/tsv-field {
  ret=${1//[$'\t\n']/ }
}

# Строка ввода после отрисовки: «курсор\nтекст» при изменении.
function keys_help/on-render {
  [[ $BASHPID == "$$" ]] || return 0
  # Автоподсказка вставлена в текст между курсором и меткой
  # (_ble_edit_mark_active = auto_complete): в строку она не входит.
  local text=$_ble_edit_str
  if [[ ${_ble_edit_mark_active-} == auto_complete ]] && ((_ble_edit_mark > _ble_edit_ind)); then
    text=${text::_ble_edit_ind}${text:_ble_edit_mark}
  fi
  local cur=$_ble_edit_ind:$text
  if ! keys_help/marked; then
    if [[ $cur != "$_keys_help_line_last" ]]; then
      keys_help/invalidate "$_keys_help_line_file"
      keys_help/invalidate "$_keys_help_cands_file"
      _keys_help_line_last= _keys_help_cands_last=
    fi
    return 0
  fi
  # Слова: пустой файл допустим, если слов нет (запомнено как «\n»).
  if [[ ! -e $_keys_help_words_file || $_keys_help_mark -nt $_keys_help_words_file ]] ||
     [[ ! -s $_keys_help_words_file && $_keys_help_words_last != $'\n' ]]; then
    keys_help/write-words force
  fi
  [[ $cur == "$_keys_help_line_last" ]] && ! keys_help/stale "$_keys_help_line_file" && return 0
  printf '%s\n%s' "$_ble_edit_ind" "$text" 2>/dev/null > "$_keys_help_line_file" || return 0
  _keys_help_line_last=$cur
}

# Аббревиатуры ble-sabbrev строками TSV — только при смене их версии.
function keys_help/collect-sabbrev {
  [[ ${_ble_complete_sabbrev_version-} ]] || return 0
  [[ $_ble_complete_sabbrev_version == "$_keys_help_sabbrev_version" ]] && return 0
  local out= key value ret keys
  ble/gdict#keys _ble_complete_sabbrev
  keys=("${ret[@]}")
  for key in "${keys[@]}"; do
    ble/gdict#get _ble_complete_sabbrev "$key" || continue
    value=${ret#*:}
    keys_help/tsv-field "$key"; key=$ret
    keys_help/tsv-field "$value"
    out+=sabbrev$'\t'$key$'\t'$ret$'\n'
  done
  _keys_help_sabbrev_lines=$out
  _keys_help_sabbrev_version=$_ble_complete_sabbrev_version
}

# Слова оболочки: аббревиатуры, псевдонимы (BASH_ALIASES), функции
# (compgen -A function без имён с / и с ведущим _). Файл пишется только
# при изменении содержимого или с аргументом force.
function keys_help/write-words {
  keys_help/ensure-dirs || return 0
  [[ ${1-} == force ]] && _keys_help_words_last=
  keys_help/collect-sabbrev
  local out=$_keys_help_sabbrev_lines name ret
  for name in "${!BASH_ALIASES[@]}"; do
    keys_help/tsv-field "${BASH_ALIASES[$name]}"
    out+=alias$'\t'$name$'\t'$ret$'\n'
  done
  # compgen пишет в файл, а не в подстановку $(…): без fork.
  local tmp=$_keys_help_dump_dir/functions.tmp
  local -a funcs=()
  compgen -A function 2>/dev/null > "$tmp" && mapfile -t funcs < "$tmp"
  for name in "${funcs[@]}"; do
    [[ $name == _* || $name == */* ]] && continue
    out+=function$'\t'$name$'\t'$'\n'
  done
  [[ $out == "$_keys_help_words_last" ]] && return 0
  printf '%s' "$out" 2>/dev/null > "$_keys_help_words_file" || return 0
  # Пустой набор слов отличается от «ещё не писали».
  _keys_help_words_last=${out:-$'\n'}
}

# Кандидаты дополнения ble.sh: «COMPV\nкандидат\n…» при изменении.
# Переменные COMPV, cand_count и cand_word — локальные вызывающего
# ble/complete/candidates/generate, видны здесь по динамической области.
function keys_help/on-cands {
  [[ $BASHPID == "$$" ]] || return 0
  ((${cand_count:-0} > 0)) || return 0
  keys_help/marked || return 0
  keys_help/ensure-dirs || return 0
  local out
  printf -v out '%s\n' "${COMPV-}" "${cand_word[@]}"
  [[ $out == "$_keys_help_cands_last" ]] && ! keys_help/stale "$_keys_help_cands_file" && return 0
  printf '%s' "$out" 2>/dev/null > "$_keys_help_cands_file" || return 0
  _keys_help_cands_last=$out
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
  _keys_help_last_base=
  keys_help/write active
}

function keys_help/precmd {
  keys_help/read-env-names
  keys_help/update-env-json
  keys_help/write active
  if keys_help/marked; then
    keys_help/write-words
  elif [[ $_keys_help_words_last ]]; then
    # Команда без наблюдения могла завести слова: прежний файл неверен.
    keys_help/invalidate "$_keys_help_words_file"
    _keys_help_words_last=
  fi
}

function keys_help/preexec {
  keys_help/update-env-json
  keys_help/write exec "$1"
}

function keys_help/exit {
  [[ $BASHPID == "$$" ]] || return 0
  command rm -rf -- "$_keys_help_record" "$_keys_help_line_file" "$_keys_help_words_file" \
    "$_keys_help_cands_file" "$_keys_help_dump_dir" 2>/dev/null
  # Каталог панели не удаляется: его создаёт и наблюдает просмотрщик
  # (inotify), после удаления наблюдение пропало бы.
}

# Проверка внутренних функций ble.sh, на которые ставятся обёртки: без
# функций смены keymap и привязок модуль не пишет ничего, без отрисовки
# и дополнения — не пишет строку и кандидатов. Предупреждение — в stderr.
function keys_help/missing {
  local f missing=
  for f; do ble/is-function "$f" || missing+=" $f"; done
  [[ $missing ]] || return 1
  ble/util/print "keys-help: в ble.sh $BLE_VERSION нет функций:$missing" >&2
}
if keys_help/missing ble/decode/keymap/push ble/decode/keymap/pop \
    ble/widget/.EDIT_COMMAND ble/widget/.SHELL_COMMAND; then
  ble/util/print "keys-help: запись контекста отключена" >&2
  return 0
fi

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

# Строка ввода: ble.sh вызывает отрисовку после каждой порции ввода.
if ! keys_help/missing ble/textarea#render; then
  ble/function#advice after ble/textarea#render 'keys_help/on-render'
fi
# Кандидаты: функция появляется с загрузкой модуля дополнения.
function keys_help/complete-load {
  keys_help/missing ble/complete/candidates/generate && return 0
  ble/function#advice after ble/complete/candidates/generate 'keys_help/on-cands'
}
blehook complete_load!=keys_help/complete-load
# Модуль дополнения уже загружен (повторное подключение модуля).
ble/is-function ble/complete/candidates/generate && keys_help/complete-load

blehook PRECMD!=keys_help/precmd
blehook PREEXEC!=keys_help/preexec
blehook ATTACH!=keys_help/notify
blehook EXIT!=keys_help/exit
