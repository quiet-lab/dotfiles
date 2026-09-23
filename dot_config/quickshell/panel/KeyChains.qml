// Индикатор цепочки с выходом (спецификация qs-key-chains): состояние
// открытого режима клавиатуры демона workspaced. Режим живёт в подкартах
// Hyprland `ws-sticky:<цепочка>/<состояние>/…`, поэтому индикатор следит
// за событием композитора submap: имя с префиксом ws-sticky: показывает
// карточку этого состояния, пустое и любое другое имя скрывает её. При старте
// панель один раз читает `hyprctl submap`, чтобы после перезапуска внутри
// режима карточка была на месте. Опроса нет.
// Клавиши и подписи состояний даёт раздел sticky вывода
// `workspaced keys --json`; команда запускается при входе в режим и при
// старте внутри него, переходы между состояниями обходятся без неё. Пока
// команда выполняется или если она завершилась ошибкой, карточка показывает
// путь из имени подкарты. Карточку рисует KeyChainsWindow; IPC-цель chains
// с функцией state сообщает состояние для проверки.
pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

QtObject {
    id: svc

    readonly property string prefix: "ws-sticky:"
    // Текущая подкарта композитора; пустая строка — подкарты нет.
    property string submap: ""
    readonly property bool shown: svc.submap.startsWith(svc.prefix)
    // Раздел sticky вывода keys --json: [{ submap, path, keys: [{ key, label, desc, exit }] }].
    property var states: []
    // Текст ошибки последней загрузки; пустая строка — ошибки нет.
    property string error: ""
    property bool loading: false
    // Положение и размер карточки для проверки по IPC; пишет KeyChainsWindow.
    property string view: ""

    // Состояние по имени подкарты; null, если его нет в загруженном перечне.
    readonly property var current: {
        for (const s of svc.states)
            if (s.submap === svc.submap) return s;
        return null;
    }
    // Путь подписей от корня; без загруженного перечня — имена состояний
    // из имени подкарты.
    readonly property var path: svc.current ? svc.current.path
                                            : (svc.shown ? svc.submap.substring(svc.prefix.length).split("/") : [])
    readonly property var keys: svc.current ? (svc.current.keys || []) : []
    // Корневое состояние: Backspace в нём закрывает режим.
    readonly property bool atRoot: svc.submap.indexOf("/") < 0

    // Смена подкарты: при входе в режим (из подкарты без префикса) перечень
    // загружается заново — конфиг мог измениться с прошлого входа.
    function setSubmap(name) {
        const was = svc.shown;
        svc.submap = name;
        if (svc.shown && !was) svc.load();
    }

    // Части результата процесса: вывод и код выхода приходят отдельными
    // событиями в произвольном порядке, разбор — когда пришли все три.
    property string outText: ""
    property string errText: ""
    property int exitCode: 0
    property bool outDone: false
    property bool errDone: false
    property bool exited: false

    function load() {
        // Загрузка уже идёт: её результат и покажем.
        if (svc.proc.running) return;
        svc.outDone = false;
        svc.errDone = false;
        svc.exited = false;
        svc.loading = true;
        svc.proc.running = true;
    }

    function finish() {
        if (!svc.outDone || !svc.errDone || !svc.exited) return;
        svc.loading = false;
        if (svc.exitCode !== 0) {
            svc.error = svc.errText.trim() !== "" ? svc.errText.trim()
                                                  : "workspaced keys --json завершилась с кодом " + svc.exitCode;
            return;
        }
        try {
            const v = JSON.parse(svc.outText);
            svc.states = v.sticky || [];
            svc.error = "";
        } catch (e) {
            svc.error = "Вывод workspaced keys --json не разобран: " + e;
        }
    }

    property Process proc: Process {
        command: [Quickshell.env("HOME") + "/.local/bin/workspaced", "keys", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                svc.outText = text;
                svc.outDone = true;
                svc.finish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                svc.errText = text;
                svc.errDone = true;
                svc.finish();
            }
        }
        onExited: (code) => {
            svc.exitCode = code;
            svc.exited = true;
            svc.finish();
        }
    }

    // Начальная подкарта: один раз при старте панели. `hyprctl submap`
    // печатает default, когда подкарты нет.
    property Process initial: Process {
        command: ["hyprctl", "submap"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                svc.setSubmap(name === "default" ? "" : name);
            }
        }
    }

    // Событие submap>>имя приходит при каждой смене подкарты; закрытие
    // подкарты — submap>> с пустым именем.
    property Connections events: Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name !== "submap") return;
            svc.setSubmap(ev.data || "");
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "chains"
        // Состояние для проверки: «hidden» либо «shown <подкарта> rows=<число
        // строк клавиш> card=x,y WxH», затем признак загрузки и текст ошибки.
        function state(): string {
            if (!svc.shown) return "hidden";
            return "shown " + svc.submap + " rows=" + svc.keys.length
                + (svc.view !== "" ? " " + svc.view : "")
                + (svc.loading ? " loading" : "") + (svc.error !== "" ? " error=" + svc.error : "");
        }
    }
}
