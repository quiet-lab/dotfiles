// Подсказка клавиш сессии (спецификация qs-keys-help): состояние окна
// и перечень цепочек по группам. Перечень даёт команда
// `workspaced keys --json` — она читает конфиг демона сама и работающего
// демона не требует. Команда запускается при каждом открытии окна, поэтому
// окно показывает конфиг таким, каким он записан сейчас; опроса нет.
// Окно рисует KeysHelpWindow, открывает и закрывает его IPC-цель keys:
// `qs -c panel ipc call keys toggle` (привязка Shift+Super+/), open, close;
// функция state сообщает состояние для проверки.
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
    id: svc

    property bool shown: false
    // [{ name, keys: [{ chain, label, desc, action, source }] }].
    property var groups: []
    // Текст ошибки последней загрузки; пустая строка — ошибки нет.
    property string error: ""
    property bool loading: false

    // Части результата процесса: вывод и код выхода приходят отдельными
    // событиями в произвольном порядке, разбор — когда пришли все три.
    property string outText: ""
    property string errText: ""
    property int exitCode: 0
    property bool outDone: false
    property bool errDone: false
    property bool exited: false

    function show() {
        svc.shown = true;
        svc.load();
    }
    function hide() { svc.shown = false; }
    function toggle() { if (svc.shown) svc.hide(); else svc.show(); }

    function load() {
        // Загрузка уже идёт (окно закрыли и открыли снова быстрее, чем
        // ответила команда): её результат и покажем.
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
            svc.groups = v.groups || [];
            svc.error = "";
        } catch (e) {
            // Старый бинарник демона ключа --json не знает и печатает
            // справку в stderr с ненулевым кодом; сюда попадает только
            // вывод, который не разобрался как JSON.
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

    property IpcHandler ipc: IpcHandler {
        target: "keys"
        function toggle(): void { svc.toggle(); }
        // Имя show занято самой командой `qs ipc` (показ описания цели),
        // поэтому открытие и закрытие без переключения — open и close.
        function open(): void { svc.show(); }
        function close(): void { svc.hide(); }
        // Состояние для проверки: «shown»/«hidden», число групп и строк,
        // текст ошибки, если она есть.
        function state(): string {
            let rows = 0;
            for (const g of svc.groups) rows += (g.keys || []).length;
            return (svc.shown ? "shown" : "hidden") + " groups=" + svc.groups.length + " rows=" + rows
                + (svc.loading ? " loading" : "") + (svc.error !== "" ? " error=" + svc.error : "");
        }
    }
}
