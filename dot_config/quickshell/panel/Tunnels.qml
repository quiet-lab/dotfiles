// Состояние туннелей станции для значков трея (спецификация qs-tray-lang,
// требование «Значки туннелей»): AmneziaWG `amn0` (системная служба
// awg-quick@amn0) и OpenVPN `axata` (соединение NetworkManager).
// Состояние перечитывается только по событиям (запись docs/decisions/0007):
// для amn0 — строки потоков `ip monitor link address` (устройство появилось,
// исчезло, сменило состояние или адрес), журнала службы `journalctl -f`
// (служба запущена, готова, остановлена, упала), страна amn0 — по
// `inotifywait` (хранилище приложения, country.json); для axata — общий поток
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
    readonly property string home: Quickshell.env("HOME")

    // Состояние: state — "up", "down", "starting", "failed"; ip — адрес
    // устройства; service — состояние юнита systemd; error — текст последней
    // неудачной команды значка (пусто, если ошибки нет); noLink — причина
    // состояния «поднят, но связи нет» (строка журнала), пусто — связь есть.
    property var amn: ({ state: "down", ip: "", service: "", error: "", noLink: "", country: "", countryName: "" })
    property var axata: ({ state: "down", ip: "", service: "", error: "", noLink: "" })

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
    // Страна amn0 ({code, name}): читается отдельно от состояния и только
    // по событиям inotify — сценарий amn-country разбирает хранилище
    // приложения, на каждое событие ip monitor его запускать дорого.
    property var amnCountry: ({ code: "", name: "" })
    property bool countryPending: false
    function readCountry() {
        if (countryProc.running) { root.countryPending = true; return; }
        countryProc.running = true;
    }
    Process {
        id: countryProc
        command: [root.home + "/.local/bin/handmade-scripts/amn-country", "current"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let c = { code: "", name: "" };
                try { c = JSON.parse(text); } catch (e) { console.warn("tunnels: amn-country current: не JSON:", text); }
                root.amnCountry = { code: c.code || "", name: c.name || "" };
                root.amn = Object.assign({}, root.amn, { country: root.amnCountry.code, countryName: root.amnCountry.name });
            }
        }
        onExited: if (root.countryPending) { root.countryPending = false; countryProc.running = true; }
    }

    function merge(old, text, label) {
        try {
            const s = JSON.parse(text);
            if (label === "amn0") {
                s.country = root.amnCountry.code;
                s.countryName = root.amnCountry.name;
            }
            s.error = old.error;
            // Туннель поднялся (был не поднят): прежняя ошибка действия больше
            // не актуальна. Ошибка действия над уже поднятым туннелем остаётся.
            if (s.state === "up" && old.state !== "up") s.error = "";
            // «Связи нет» имеет смысл только у поднятого туннеля и только до его
            // перезапуска: признак держится, пока туннель остаётся поднятым.
            s.noLink = s.state === "up" && old.state === "up" ? (old.noLink || "") : "";
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
        onLine: (text) => root.amnJournal(text)
    }
    Stream {
        label: "journalctl -f nm-openvpn"
        tunnel: "axata"
        // Строки OpenVPN соединения axata (идентификатор nm-openvpn): обрыв
        // по ping-restart и восстановление.
        command: ["journalctl", "-f", "-n", "0", "-q", "-o", "cat", "-t", "nm-openvpn"]
        onLine: (text) => root.axataJournal(text)
    }
    Stream {
        label: "inotifywait"
        // Страна туннеля: хранилище приложения AmneziaVPN (страна из
        // приложения) и /etc/amnezia (country.json — страна, выбранная через
        // amn-country). Реагируют строки об этих двух файлах.
        command: ["inotifywait", "-m", "-q", "-e", "close_write,moved_to,delete", "--format", "%w%f",
            root.home + "/.config/AmneziaVPN.ORG/", "/etc/amnezia/"]
        onLine: (text) => { if (text === "" || /AmneziaVPN\.conf$|country\.json$/.test(text)) root.readCountry(); }
    }
    Stream {
        label: "journalctl -f axata-vpn"
        tunnel: "axata"
        command: ["journalctl", "-f", "-n", "0", "-q", "-o", "cat", "-u", "axata-vpn.service"]
        onLine: (text) => root.readAxata()
    }

    // --- «Поднят, но связи нет» по строкам журналов (design изменения
    // tunnel-country-link). amneziawg-go с LOG_LEVEL=verbose (drop-in юнита)
    // пишет о рукопожатиях: повторная неудача — связи нет, ответ на
    // рукопожатие или keepalive от сервера — связь есть. Строки о собственных
    // отправках (keepalive каждые 25 с, initiation) состояние не перечитывают. ---
    function setNoLink(tunnel, reason) {
        const t = tunnel === "amn0" ? root.amn : root.axata;
        if ((t.noLink || "") === reason) return;
        if (reason !== "" && t.state !== "up") return;
        const s = Object.assign({}, t);
        s.noLink = reason;
        if (tunnel === "amn0") root.amn = s;
        else root.axata = s;
    }
    function amnJournal(text) {
        const retry = /Handshake did not complete after \d+ seconds, retrying \(try (\d+)\)/.exec(text);
        if (retry) {
            // Первая неудача (try 2) бывает и при потере одного пакета;
            // вторая подряд (try 3, около 10 с без ответа) — связи нет.
            if (Number(retry[1]) >= 3) root.setNoLink("amn0", text.replace(/^.*? - /, ""));
            return;
        }
        if (/Handshake did not complete after \d+ attempts, giving up/.test(text)) {
            root.setNoLink("amn0", text.replace(/^.*? - /, ""));
            return;
        }
        if (/Received handshake response|Receiving keepalive packet|Received handshake initiation/.test(text)) {
            root.setNoLink("amn0", "");
            return;
        }
        if (/Sending keepalive packet|Sending handshake initiation|Retrying handshake because|Routine: |UAPI: |DEBUG: /.test(text)) return;
        // Остальное — сообщения systemd о юните и ловушек awg-quick.
        root.readAmn();
    }
    // Только строки, за которыми OpenVPN перезапускает соединение: разовые
    // ошибки («TLS Error», «No route to host») без перезапуска связь не
    // обрывают, а снять признак может только «Initialization Sequence
    // Completed». Строки других профилей OpenVPN не различаются (идентификатор
    // общий), поэтому признак ставится, только пока axata поднят.
    function axataJournal(text) {
        if (/Inactivity timeout|SIGUSR1\[soft/.test(text)) {
            root.setNoLink("axata", text);
        } else if (/Initialization Sequence Completed/.test(text)) {
            root.setNoLink("axata", "");
        }
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
