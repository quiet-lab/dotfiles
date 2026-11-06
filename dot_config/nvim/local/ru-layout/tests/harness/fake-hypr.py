#!/usr/bin/env python3
# Двойник Hyprland для тестов: каталог <root>/<sig> с .socket.sock (запросы) и
# .socket2.sock (события). Запросы .socket.sock:
#   j/devices                            -- JSON с клавиатурой dh747-w-corne;
#   switchxkblayout <устройство> <индекс|next> -- меняет раскладку, отвечает «ok»
#                                           и рассылает подписчикам .socket2.sock
#                                           activelayout>>dh747-w-corne,<раскладка>.
# При подключении к .socket2.sock подписчик получает текущее состояние строкой activelayout.
# Завершается по SIGTERM, удаляет свои сокеты и каталог.
# Запуск: fake-hypr.py <root> <sig> <"English (US)"|"Russian">
import json
import os
import signal
import socket
import sys
import threading

root, sig, keymap = sys.argv[1:4]
DEVICE = "dh747-w-corne"
KEYMAPS = ["English (US)", "Russian"]
base = os.path.join(root, sig)
os.makedirs(base, exist_ok=True)

lock = threading.Lock()
state = {"idx": 0 if keymap.startswith("English") else 1}
clients = []


def devices():
    return {
        "keyboards": [
            {
                "name": DEVICE,
                "main": True,
                "active_layout_index": state["idx"],
                "active_keymap": KEYMAPS[state["idx"]],
                "layout": "us",
            }
        ],
        "mice": [],
    }


def broadcast():
    line = f"activelayout>>{DEVICE},{KEYMAPS[state['idx']]}\n".encode()
    for c in list(clients):
        try:
            c.sendall(line)
        except OSError:
            clients.remove(c)


def handle_cmd(cmd):
    cmd = cmd.strip()
    if cmd == "j/devices":
        with lock:
            return json.dumps(devices())
    parts = cmd.split()
    if len(parts) == 3 and parts[0] == "switchxkblayout" and parts[1] == DEVICE:
        with lock:
            if parts[2] == "next":
                state["idx"] = (state["idx"] + 1) % len(KEYMAPS)
            elif parts[2].isdigit() and int(parts[2]) < len(KEYMAPS):
                state["idx"] = int(parts[2])
            else:
                return "layout idx out of range"
            broadcast()
        return "ok"
    return "unknown request"


def serve(path, handler):
    s = socket.socket(socket.AF_UNIX)
    s.bind(path)
    s.listen(8)

    def loop():
        while True:
            c, _ = s.accept()
            threading.Thread(target=handler, args=(c,), daemon=True).start()

    threading.Thread(target=loop, daemon=True).start()


def query(c):
    cmd = c.recv(4096).decode()
    c.sendall(handle_cmd(cmd).encode())
    c.close()


def events(c):
    with lock:
        clients.append(c)
        c.sendall(f"activelayout>>{DEVICE},{KEYMAPS[state['idx']]}\n".encode())


serve(os.path.join(base, ".socket.sock"), query)
serve(os.path.join(base, ".socket2.sock"), events)
print("ready", flush=True)


def bye(*_):
    for c in clients:
        try:
            c.close()
        except OSError:
            pass
    for f in (".socket.sock", ".socket2.sock"):
        try:
            os.unlink(os.path.join(base, f))
        except OSError:
            pass
    os.rmdir(base)
    os._exit(0)


signal.signal(signal.SIGTERM, bye)
signal.pause()
