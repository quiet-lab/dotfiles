#!/usr/bin/env python3
"""Тест поставщика контекста ble.sh (задача 6.8 изменения herdr-keys-help).

Запуск одной командой из любого каталога:

    python3 dot_config/herdr/plugins/keys-help/tests/test_ble_provider.py

Живой ble.sh (~/.local/share/blesh) запускается под псевдотерминалом
с временными HOME, XDG_RUNTIME_DIR и HERDR_PANE_ID; ~/.blerc временного
HOME — ссылка на dot_blerc источника, модуль — ссылка на
dot_config/blesh/keys-help.bash. Проверяются записи канала при смене
keymap, exec, widget (-x и -c), PRECMD, дампы `ble-bind -P`, уборка
при выходе и бездействие модуля вне herdr.

Отсутствие внешних процессов на смену keymap проверяется счётчиком
pid отдельного пространства имён pid (/proc/sys/kernel/ns_last_pid):
тест перезапускает себя под `unshare --pid`, и каждый fork оболочки
увеличивает счётчик.

Все ожидания — до события: появление и запись файла (inotify), вывод
псевдотерминала, выход процесса. Длительность каждого ожидания
печатается как замер. Зависание ловит только внешний предел прогона
целиком (`timeout` при перезапуске под unshare).
"""

import ctypes
import errno
import fcntl
import json
import os
import pty
import re
import select
import shutil
import struct
import sys
import tempfile
import termios
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# Корень источника chezmoi: tests → keys-help → plugins → herdr → dot_config → корень.
SRC = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
BLERC = os.path.join(SRC, "dot_blerc")
MODULE = os.path.join(SRC, "dot_config", "blesh", "keys-help.bash")
BLESH = os.path.expanduser("~/.local/share/blesh/ble.sh")
PANE_ID = "w1:p1"
# Внешний предел прогона целиком, секунды.
RUN_LIMIT = os.environ.get("KH_RUN_LIMIT", "300")

IN_CREATE = 0x100
IN_CLOSE_WRITE = 0x8
IN_MOVED_TO = 0x80
IN_DELETE = 0x200
IN_DELETE_SELF = 0x400
WATCH_MASK = IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_TO | IN_DELETE | IN_DELETE_SELF


def reexec_in_pidns():
    """Перезапуск под отдельным пространством имён pid с внешним пределом."""
    env = dict(os.environ, KH_TEST_PIDNS="1")
    cmd = ["unshare", "--map-current-user", "--pid", "--fork", "--mount-proc",
           "timeout", RUN_LIMIT, sys.executable, "-I", "-u", os.path.abspath(__file__)]
    os.execvpe(cmd[0], cmd, env)


def ns_last_pid():
    with open("/proc/sys/kernel/ns_last_pid") as f:
        return int(f.read())


class Inotify:
    def __init__(self):
        self.libc = ctypes.CDLL("libc.so.6", use_errno=True)
        self.fd = self.libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1")
        self.watched = {}

    def watch(self, path):
        if path in self.watched or not os.path.isdir(path):
            return
        wd = self.libc.inotify_add_watch(self.fd, path.encode(), WATCH_MASK)
        if wd >= 0:
            self.watched[path] = wd

    def drain(self):
        try:
            while os.read(self.fd, 65536):
                pass
        except BlockingIOError:
            pass
        # Снятые watch (каталог удалён) переустанавливаются при следующем watch().
        self.watched = {p: w for p, w in self.watched.items() if os.path.isdir(p)}


class Shell:
    """bash с ble.sh под псевдотерминалом."""

    def __init__(self, env, rcfile):
        pid, fd = pty.fork()
        if pid == 0:
            os.execve("/bin/bash", ["bash", "--rcfile", rcfile, "-i"], env)
        self.pid, self.fd = pid, fd
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        os.set_blocking(fd, False)
        self.output = b""
        self.status = None

    def send(self, data):
        os.write(self.fd, data)

    def pump(self):
        try:
            while True:
                chunk = os.read(self.fd, 65536)
                if not chunk:
                    break
                self.output += chunk
        except BlockingIOError:
            pass
        except OSError as e:
            if e.errno != errno.EIO:
                raise
            return False
        return True


class Harness:
    def __init__(self, tmp, pane_id, env_vars=None, extra_env=None):
        self.tmp = tmp
        self.home = os.path.join(tmp, "home")
        self.run = os.path.join(tmp, "run")
        os.makedirs(os.path.join(self.home, ".config", "blesh"))
        os.makedirs(self.run, mode=0o700)
        os.makedirs(os.path.join(tmp, "cache"))
        os.symlink(BLERC, os.path.join(self.home, ".blerc"))
        os.symlink(MODULE, os.path.join(self.home, ".config", "blesh", "keys-help.bash"))
        self.trace = os.path.join(tmp, "trace")
        self.forks = os.path.join(tmp, "forks")
        self.forks_line = os.path.join(tmp, "forks-line")
        rc = os.path.join(tmp, "bashrc")
        with open(rc, "w") as f:
            f.write(f"""
source -- {BLESH} --attach=none
# Тестовые привязки: -x ждёт строку внутри привязки, -c выполняет команду.
function kh_fake_widget {{ IFS= read -r kh_widget_line; }}
ble-bind -m vi_imap -x M-k kh_fake_widget
ble-bind -m vi_imap -c M-j 'head -n1'
# Наблюдение: каждая сделанная запись модуля — строкой в файл трассы.
if declare -F keys_help/write >/dev/null; then
  # Каждая сделанная запись — строкой в файл трассы; число fork за вызов
  # (счётчик pid пространства имён, чтение встроенным read) — в файл forks.
  ble/function#advice around keys_help/write '
    local kh_a kh_b kh_prev=$_keys_help_last
    read -r kh_a < /proc/sys/kernel/ns_last_pid
    ble/function#advice/do
    read -r kh_b < /proc/sys/kernel/ns_last_pid
    [[ $_keys_help_last != "$kh_prev" ]] && printf "%s\\n" "$_keys_help_last" >> {self.trace}
    printf "%d %s\\n" "$((kh_b - kh_a))" "$*" >> {self.forks}'
  # Число fork за вызов обработчиков строки ввода, слов и кандидатов.
  for kh_f in keys_help/on-render keys_help/on-cands keys_help/write-words; do
    ble/function#advice around "$kh_f" '
      local kh_a kh_b
      read -r kh_a < /proc/sys/kernel/ns_last_pid
      ble/function#advice/do
      read -r kh_b < /proc/sys/kernel/ns_last_pid
      printf "%d %s\\n" "$((kh_b - kh_a))" "${{ADVICE_WORDS[0]}}" >> {self.forks_line}'
  done
fi
# Слова оболочки для .words и кандидатов дополнения.
alias khal='ls -la'
ble-sabbrev gst='git status'
function kh_fake_other {{ :; }}
# vi-режим, как в dot_bashrc
set -o vi
PS1='kh$ '
ble-attach
""")
        self.env = {
            "HOME": self.home,
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "USER": os.environ.get("USER", "user"),
            "TERM": "xterm-256color",
            "LANG": "C.UTF-8",
            "XDG_RUNTIME_DIR": self.run,
            "XDG_CACHE_HOME": os.path.join(tmp, "cache"),
            "XDG_STATE_HOME": os.path.join(tmp, "state"),
            "XDG_DATA_HOME": os.path.join(tmp, "data"),
            "XDG_CONFIG_HOME": os.path.join(self.home, ".config"),
        }
        if pane_id is not None:
            self.env["HERDR_PANE_ID"] = pane_id
        self.base = os.path.join(self.run, "herdr-keys-help")
        self.pane_dir = os.path.join(self.base, "panes", pane_id or "-")
        self.env.update(extra_env or {})
        if env_vars is not None:
            # Файл env-vars просмотрщика уже есть до старта оболочки.
            os.makedirs(self.base)
            with open(os.path.join(self.base, "env-vars"), "w") as f:
                f.write(env_vars)
        self.ino = Inotify()
        self.shell = Shell(self.env, rc)
        self.record_path = os.path.join(self.pane_dir, f"ble-{self.shell.pid}.json")
        self.dump_dir = os.path.join(self.base, "ble", str(self.shell.pid))

    def _watch_chain(self):
        for d in (self.tmp, self.run, self.base, os.path.join(self.base, "panes"), self.pane_dir,
                  os.path.join(self.base, "ble"), self.dump_dir):
            self.ino.watch(d)

    def wait(self, what, predicate):
        """Ждать, пока predicate() не вернёт истину; будит inotify, вывод, выход."""
        start = time.monotonic()
        while True:
            self._watch_chain()
            result = predicate()
            if result:
                print(f"  замер: {what} — {time.monotonic() - start:.3f} с")
                return result
            fds = [self.ino.fd]
            if self.shell.status is None:
                fds.append(self.shell.fd)
            r, _, _ = select.select(fds, [], [])
            if self.ino.fd in r:
                self.ino.drain()
            if self.shell.fd in r:
                if not self.shell.pump():
                    os.close(self.shell.fd)
                    _, self.shell.status = os.waitpid(self.shell.pid, 0)
            if self.shell.status is not None and not predicate():
                raise AssertionError(f"оболочка завершилась, не дождавшись: {what}")

    def record(self):
        try:
            with open(self.record_path) as f:
                return json.loads(f.read())
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def wait_record(self, what, **expect):
        def check():
            rec = self.record()
            if rec and all(rec.get(k) == v for k, v in expect.items()):
                return rec
            return None
        return self.wait(what, check)

    def plain(self):
        """Вывод терминала без управляющих последовательностей CSI и OSC."""
        return re.sub(rb"\x1b\[[0-9;?>=]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[()][0-9A-Za-z]|\x1b[78=>]",
                      b"", self.shell.output)

    def trace_lines(self):
        try:
            return open(self.trace).read().splitlines()
        except FileNotFoundError:
            return []

    def module_forks(self):
        """Пары (число fork, аргументы) по вызовам keys_help/write."""
        out = []
        for line in open(self.forks).read().splitlines():
            n, _, args = line.partition(" ")
            out.append((int(n), args))
        return out

    def wait_exit(self):
        def done():
            return self.shell.status is not None
        return self.wait("выход оболочки", done)


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print(f"ok  {msg}")


def test_in_herdr(tmp):
    print("== оболочка в панели herdr")
    h = Harness(tmp, PANE_ID)
    pid = h.shell.pid

    rec = h.wait_record("первая запись active vi_imap", state="active", mode="vi_imap")
    check(rec["v"] == 1 and rec["program"] == "ble" and rec["pid"] == pid,
          "запись ble-<pid>.json: v=1, program=ble, pid оболочки")
    check(rec["command"] is None and rec["server"] is None and rec["env"] == {},
          "active: command и server — null, env пуст без файла env-vars")
    table = rec["table"]
    check(table == os.path.join(h.dump_dir, "vi_imap.bind") and os.path.isfile(table),
          "поле table указывает на дамп vi_imap")
    dump = open(table).read()
    for line in ("ble-bind -m 'vi_imap' -x M-f fzf-file-widget",
                 "ble-bind -m 'vi_imap' -x M-h fzf-history-widget",
                 "ble-bind -m 'vi_imap' -x M-r __atuin_history",
                 "ble-bind -m 'vi_imap' -x M-t tv_shell_history",
                 "ble-bind -m 'vi_imap' -x C-M-t tv_smart_autocomplete"):
        check(line in dump, f"дамп -P содержит «{line}» (привязки dot_blerc целы)")
    check("ble-bind -m 'vi_imap' -c M-d" in dump, "дамп -P содержит -c M-d")

    # Смена keymap: Esc → vi_nmap, i → vi_imap, дважды; счётчик pid не растёт.
    before = ns_last_pid()
    for n in (1, 2):
        h.send_key(b"\x1b")
        rec = h.wait_record(f"Esc → vi_nmap ({n})", state="active", mode="vi_nmap")
        check(rec["table"].endswith("/vi_nmap.bind") and os.path.isfile(rec["table"]),
              f"vi_nmap ({n}): дамп записан и указан в table")
        h.send_key(b"i")
        h.wait_record(f"i → vi_imap ({n})", state="active", mode="vi_imap")
    after = ns_last_pid()
    print(f"  замер: fork оболочки за смены keymap, всего с ble.sh — {after - before}")
    calls = h.module_forks()
    check(calls and all(n == 0 for n, _ in calls[1:]),
          f"вызовы модуля на смену keymap без внешних процессов ({len(calls) - 1} вызовов)")
    check("ble-bind -m 'vi_nmap'" in open(os.path.join(h.dump_dir, "vi_nmap.bind")).read(),
          "дамп vi_nmap — вывод ble-bind -m vi_nmap -P")

    # Поиск по истории: C-r → isearch, C-g → снова vi_imap.
    h.send_key(b"\x12")
    h.wait_record("C-r → isearch", state="active", mode="isearch")
    h.send_key(b"\x07")
    h.wait_record("C-g → vi_imap", state="active", mode="vi_imap")
    check(all(n == 0 for n, _ in h.module_forks()[1:]), "isearch без внешних процессов в модуле")
    check(os.path.isfile(os.path.join(h.dump_dir, "isearch.bind")), "дамп isearch записан")

    # Только смена: повторная запись того же keymap не делается.
    writes = h.trace_lines()
    check(all(a != b for a, b in zip(writes, writes[1:])), "запись только при изменении")

    # exec: команда из строки, затем PRECMD.
    h.send_key(b"head -n1\r")
    rec = h.wait_record("PREEXEC → exec", state="exec")
    check(rec["command"] == "head -n1", "exec: command — командная строка")
    h.send_key(b"x\r")
    h.wait_record("PRECMD → active", state="active", mode="vi_imap")

    # widget -x: запись до выполнения, active после.
    h.send_key(b"\x1bk")
    rec = h.wait_record("M-k → widget", state="widget")
    check(rec["command"] == "kh_fake_widget", "widget -x: command — команда привязки")
    h.send_key(b"y\n")
    h.wait_record("после -x → active", state="active", mode="vi_imap")

    # widget -c: widget → active → exec → PRECMD active (по трассе записей).
    h.wait("трасса: active после -x", lambda: h.trace_lines()[-1:] == ["active vi_imap "])
    mark = len(h.trace_lines())
    h.send_key(b"\x1bj")
    h.wait_record("M-j → exec", state="exec", command="head -n1")
    h.send_key(b"z\r")
    h.wait_record("после -c → active", state="active", mode="vi_imap")
    seq = h.wait("трасса -c", lambda: (lambda t: t if len(t) >= 4 else None)(h.trace_lines()[mark:]))
    check(seq[:4] == ["widget vi_imap head -n1", "active vi_imap ", "exec vi_imap head -n1",
                      "active vi_imap "],
          f"-c: записи widget, active, exec, active ({seq})")

    # Подстановки env: файл env-vars просмотрщика перечитывается в PRECMD.
    with open(os.path.join(h.base, "env-vars"), "w") as f:
        f.write("KH_TEST_VAR\nnot-a-name\n")
    h.send_key(b"export KH_TEST_VAR='a\"b'\r")
    h.wait_record("exec export", state="exec")
    h.wait_record("PRECMD после export", state="active")
    h.send_key(b"head -n1\r")
    rec = h.wait_record("exec с env", state="exec", command="head -n1")
    check(rec["env"] == {"KH_TEST_VAR": 'a"b'}, f"env записи из env-vars ({rec['env']})")
    h.send_key(b"w\r")
    h.wait_record("active после env", state="active")

    # Выход: запись и каталог дампов удалены.
    h.send_key(b"exit\r")
    h.wait_exit()
    check(not os.path.exists(h.record_path), "при выходе запись удалена")
    check(not os.path.exists(h.dump_dir), "при выходе каталог дампов удалён")
    check(os.path.isdir(h.pane_dir), "каталог панели остаётся (его наблюдает просмотрщик)")


def read_file(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return None


def test_input_line(tmp):
    print("== строка ввода, слова и кандидаты (D17)")
    h = Harness(tmp, PANE_ID)
    pid = h.shell.pid
    line = os.path.join(h.pane_dir, f"ble-{pid}.line")
    words = os.path.join(h.pane_dir, f"ble-{pid}.words")
    cands = os.path.join(h.pane_dir, f"ble-{pid}.cands")
    marker = os.path.join(h.pane_dir, "viewer")
    h.wait_record("первая запись active", state="active", mode="vi_imap")

    # Без отметки: отрисовка идёт, файлов строки и слов нет. Эхо в
    # терминале выводится после обработчика отрисовки.
    h.send_key(b"ls -l")
    h.wait("эхо «ls -l» без отметки", lambda: b"ls -l" in h.plain())
    check(read_file(line) is None and read_file(words) is None, "без отметки viewer .line и .words нет")

    # Отметка есть: первое же изменение пишет строку и слова.
    open(marker, "w").close()
    h.send_key(b"\x01")  # C-a: в начало строки
    h.wait(".line: курсор 0", lambda: read_file(line) == "0\nls -l")
    h.send_key(b"\x05")  # C-e: в конец строки
    h.wait(".line: курсор 5", lambda: read_file(line) == "5\nls -l")
    w = read_file(words) or ""
    for row in ("sabbrev\tgst\tgit status", "alias\tkhal\tls -la", "function\tkh_fake_widget\t"):
        check(row in w.splitlines(), f".words содержит «{row.replace(chr(9), ' | ')}»")
    check(not any(r.split("\t")[1].startswith("_") or "/" in r.split("\t")[1]
                  for r in w.splitlines() if r.startswith("function\t")),
          ".words: функций с / и с ведущим _ нет")

    # Многострочный текст: позиция в символах, текст как есть.
    h.send_key(b" \xd1\x8e")  # пробел и «ю»
    h.wait(".line: символы, не байты", lambda: read_file(line) == "7\nls -l ю")

    # Без отметки запись не делается: файл не меняется.
    os.unlink(marker)
    before = read_file(line)
    h.send_key(b"zzz")
    h.wait("эхо «zzz» без отметки", lambda: b"zzz" in h.plain())
    check(read_file(line) == before, "без отметки .line не меняется")

    # Новая аббревиатура: .words обновляется по PRECMD.
    open(marker, "w").close()
    h.send_key(b"\x15ble-sabbrev gco='git checkout'\r")
    h.wait(".words: новая аббревиатура gco",
           lambda: "sabbrev\tgco\tgit checkout" in (read_file(words) or "").splitlines())

    # Кандидаты дополнения по TAB: COMPV первой строкой, затем кандидаты.
    h.send_key(b"kh_fa\t")
    c = h.wait(".cands для kh_fa", lambda: (lambda t: t if t and t.startswith("kh_fa\n") else None)(read_file(cands)))
    check({"kh_fake_widget", "kh_fake_other"} <= set(c.splitlines()[1:]),
          f".cands содержит kh_fake_widget и kh_fake_other ({c.splitlines()[1:]})")

    # Строка о вызове дописывается после записи файла: ждать её.
    need = {"keys_help/on-render", "keys_help/on-cands", "keys_help/write-words"}

    def all_calls():
        got = [l.split(" ", 1) for l in (read_file(h.forks_line) or "").splitlines()]
        return got if need <= {n for _, n in got} else None
    calls = h.wait("учёт вызовов обработчиков", all_calls)
    check(all(n == "0" for n, _ in calls),
          f"строка, слова и кандидаты без внешних процессов ({len(calls)} вызовов)")

    h.send_key(b"\x1b")
    h.send_key(b"S")  # vi_nmap: очистить строку, обратно в vi_imap
    h.send_key(b"exit\r")
    h.wait_exit()
    check(all(read_file(p) is None for p in (line, words, cands)), "при выходе .line, .words, .cands удалены")


def test_env_file_before_start(tmp):
    print("== файл env-vars есть до старта оболочки")
    h = Harness(tmp, PANE_ID, env_vars="KH_TEST_VAR\n", extra_env={"KH_TEST_VAR": "v"})
    h.wait_record("запись active с env", state="active", mode="vi_imap", env={"KH_TEST_VAR": "v"})
    h.send_key(b"echo KH_\"\"READY\r")
    h.wait("приглашение после echo", lambda: b"KH_READY" in h.shell.output)
    check(b"No such file" not in h.shell.output and b"env-vars.read" not in h.shell.output,
          "модуль не печатает ошибок в терминал")
    h.send_key(b"exit\r")
    h.wait_exit()
    check(not os.path.exists(h.record_path), "при выходе запись удалена")


def test_outside_herdr(tmp):
    print("== оболочка вне herdr")
    h = Harness(tmp, None)
    h.send_key(b"echo KH_\"\"READY\r")
    h.wait("приглашение вне herdr", lambda: b"KH_READY" in h.shell.output)
    h.send_key(b"exit\r")
    h.wait_exit()
    check(not os.path.exists(h.base), "вне herdr каталог канала не создаётся")


def _send_key(self, data):
    self.shell.send(data)


Harness.send_key = _send_key


def main():
    if os.environ.get("KH_TEST_PIDNS") != "1":
        reexec_in_pidns()
    for path in (BLERC, MODULE, BLESH):
        if not os.path.isfile(path):
            print(f"нет файла {path}", file=sys.stderr)
            return 2
    failed = False
    for test in (test_in_herdr, test_input_line, test_env_file_before_start, test_outside_herdr):
        tmp = tempfile.mkdtemp(prefix="kh-ble-")
        try:
            test(tmp)
        except AssertionError as e:
            failed = True
            print(f"FAIL {test.__name__}: {e}")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    print("ИТОГ:", "FAIL" if failed else "OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
