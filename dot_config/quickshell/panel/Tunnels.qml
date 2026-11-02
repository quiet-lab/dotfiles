// Состояние туннелей станции для значков трея (спецификация qs-tray-lang,
// требование «Значки туннелей»): AmneziaWG `amn0` (системная служба
// awg-quick@amn0) и OpenVPN `axata` (соединение NetworkManager).
// Состояние перечитывается только по событиям (запись docs/decisions/0007):
// для amn0 — строки потоков `ip monitor link address` (устройство появилось,
// исчезло, сменило состояние или адрес) и журнала службы `journalctl -f`
// (служба запущена, готова, остановлена, упала); для axata — общий поток
// `nmcli monitor` панели (синглтон NmMonitor) и журнал юнита axata-vpn
// (NetworkManager сообщает об отказе VPN раньше, чем юнит становится failed).
// Таймеров и опроса нет.
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string scripts: Quickshell.shellDir + "/scripts/"

    // Состояние: state — "up", "down", "starting", "failed"; ip — адрес
    // устройства; service — состояние юнита systemd; error — текст последней
    // неудачной команды значка (пусто, если ошибки нет).
    property var amn: ({ state: "down", ip: "", service: "", error: "" })
    property var axata: ({ state: "down", ip: "", service: "", error: "" })

    // --- Чтение состояния: один процесс на туннель, событие во время чтения
    // откладывает следующее чтение до конца текущего (как у плитки сети). ---
    property bool amnPending: false
    property bool axataPending: false
    function readAmn() {
        if (amnProc.running) { root.amnPending = true; return; }
        amnProc.running = true;
    }
    function readAxata() {
        if (axataProc.running) { root.axataPending = true; return; }
        axataProc.running = true;
    }
    function merge(old, text, label) {
        try {
            const s = JSON.parse(text);
            s.error = old.error;
            // Туннель поднялся (был не поднят): прежняя ошибка действия больше
            // не актуальна. Ошибка действия над уже поднятым туннелем остаётся.
            if (s.state === "up" && old.state !== "up") s.error = "";
            return s;
        } catch (e) {
            console.warn("tunnels: " + label + ": не JSON:", text);
            return old;
        }
    }

    Process {
        id: amnProc
        command: [root.scripts + "tunnelstate", "amn0"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.amn = root.merge(root.amn, text, "amn0")
        }
        onExited: if (root.amnPending) { root.amnPending = false; amnProc.running = true; }
    }
    Process {
        id: axataProc
        command: [root.scripts + "tunnelstate", "axata"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.axata = root.merge(root.axata, text, "axata")
        }
        onExited: if (root.axataPending) { root.axataPending = false; axataProc.running = true; }
    }

    // --- Источники событий ---
    Connections {
        target: NmMonitor
        function onEvent() { root.readAxata(); }
    }

    // Поток, который перезапускается по выходу; пять мгновенных выходов подряд
    // (меньше секунды с запуска) останавливают попытки с предупреждением
    // в журнале, как у nmcli monitor.
    component Stream: Process {
        id: stream
        property string label
        // Туннель, состояние которого обновляет поток (для предупреждения).
        property string tunnel: "amn0"
        property double started: 0
        property int failures: 0
        signal line(string text)
        running: true
        stdout: SplitParser { onRead: (data) => stream.line(data) }
        onRunningChanged: if (running) stream.started = Date.now()
        onExited: {
            if (Date.now() - stream.started >= 1000) stream.failures = 0;
            else stream.failures++;
            if (stream.failures < 5) {
                stream.running = true;
                // Пока поток не работал, изменения могли пройти мимо.
                stream.line("");
            } else {
                console.warn("tunnels: " + stream.label + " не запускается, состояние " + stream.tunnel + " больше не обновляется");
            }
        }
    }
    Stream {
        label: "ip monitor"
        command: ["ip", "monitor", "link", "address"]
        // Поток сообщает обо всех устройствах; на amn0 реагируют строки с его
        // именем (и пустая строка после перезапуска потока).
        onLine: (text) => { if (text === "" || /\bamn0\b/.test(text)) root.readAmn(); }
    }
    Stream {
        label: "journalctl -f"
        // -n 0: только новые строки; -u добавляет и сообщения systemd о юните
        // (запущен, готов, остановлен, упал).
        command: ["journalctl", "-f", "-n", "0", "-q", "-o", "cat", "-u", "awg-quick@amn0.service"]
        onLine: (text) => root.readAmn()
    }
    Stream {
        label: "journalctl -f axata-vpn"
        tunnel: "axata"
        command: ["journalctl", "-f", "-n", "0", "-q", "-o", "cat", "-u", "axata-vpn.service"]
        onLine: (text) => root.readAxata()
    }

    // --- Действия значков: команда выполняется процессом панели, свой процесс
    // у каждого туннеля; код выхода и последняя строка вывода ошибок попадают
    // в error туннеля и показываются в подсказке. Пока действие выполняется,
    // второе над тем же туннелем не запускается: act возвращает false,
    // подсказка показывает «выполняется действие» (свойства amnBusy, axataBusy). ---
    readonly property bool amnBusy: amnAction.running
    readonly property bool axataBusy: axataAction.running
    function act(tunnel, args) {
        const proc = tunnel === "amn0" ? amnAction : axataAction;
        if (proc.running) return false;
        proc.command = args;
        proc.running = true;
        return true;
    }
    function setError(tunnel, text) {
        const s = Object.assign({}, tunnel === "amn0" ? root.amn : root.axata);
        s.error = text;
        if (tunnel === "amn0") root.amn = s;
        else root.axata = s;
    }
    component ActionProc: Process {
        id: action
        required property string tunnel
        // Итог подводится, когда пришли и код выхода, и весь вывод ошибок:
        // порядок этих двух событий не гарантирован.
        property int code: 0
        property int pending: 0
        onRunningChanged: if (running) action.pending = 2
        function finish() {
            if (--action.pending > 0) return;
            root.setError(action.tunnel, action.code === 0 ? "" : (err.text.trim().split("\n").pop() || ("код выхода " + action.code)));
            if (action.tunnel === "amn0") root.readAmn();
            else root.readAxata();
        }
        stderr: StdioCollector { id: err; onStreamFinished: action.finish() }
        onExited: (exitCode) => { action.code = exitCode; action.finish(); }
    }
    ActionProc { id: amnAction; tunnel: "amn0" }
    ActionProc { id: axataAction; tunnel: "axata" }
}
