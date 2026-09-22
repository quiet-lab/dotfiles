// Связь с демоном workspaced (спецификация ws-daemon, «Состояние для панели»;
// design D12 изменения workspace-daemon): подписка по сокету
// $XDG_RUNTIME_DIR/workspaced/sock, строки JSON. Состояние столов приходит
// целиком при подключении и после каждого изменения; событие show-sessions
// открывает окно выбора сессии. Без демона панель показывает только окна
// и подключается заново, как только демон снова заведёт сокет.
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
    id: wsd

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property string socketPath: wsd.runtimeDir + "/workspaced/sock"
    // Объект подключения пересоздаётся при каждой попытке (см. connect ниже).
    property var socket: null
    readonly property bool connected: wsd.socket ? wsd.socket.connected : false
    // Номер стола → { workspaces: [{ name, icon, active, apps, windows }], active }.
    property var desktops: ({})
    property int currentDesktop: 0
    // Последний список сессий (от show-sessions или ответа session list).
    property var sessions: []
    signal showSessions(var list)

    function send(obj) {
        if (!wsd.connected) return;
        wsd.socket.write(JSON.stringify(obj) + "\n");
    }
    function raise(ws, desktop) { send({ cmd: "raise", workspace: ws, desktop: desktop }); }
    function remove(ws, desktop) { send({ cmd: "remove", workspace: ws, desktop: desktop }); }
    function sessionLoad(name) { send({ cmd: "session", op: "load", name: name }); }
    function sessionSave(name) { send({ cmd: "session", op: "save", name: name }); refreshSessions(); }
    function refreshSessions() { send({ cmd: "session", op: "list" }); }

    function handle(line) {
        let msg;
        try { msg = JSON.parse(line); } catch (e) { console.warn("workspaced: не JSON:", line); return; }
        if (msg.event === "state") {
            wsd.desktops = msg.desktops || {};
            wsd.currentDesktop = msg.current_desktop || 0;
        } else if (msg.event === "show-sessions") {
            wsd.sessions = msg.sessions || [];
            wsd.showSessions(wsd.sessions);
        } else if (msg.sessions !== undefined) {
            wsd.sessions = msg.sessions || [];
        } else if (msg.ok === false) {
            console.warn("workspaced:", msg.error);
        }
    }

    // Попытка подключения. Socket из Quickshell.Io после неудачной попытки
    // больше не подключается: ни повторное присваивание connected, ни смена path
    // новой попытки не дают (проверено на живом демоне 22.09.2026), поэтому
    // объект каждый раз создаётся заново.
    function connect() {
        const old = wsd.socket;
        wsd.socket = null;
        if (old) { old.connected = false; old.destroy(); }
        wsd.socket = wsd.socketComponent.createObject(wsd);
    }

    property Component socketComponent: Component {
        Socket {
            path: wsd.socketPath
            connected: true
            parser: SplitParser {
                splitMarker: "\n"
                onRead: (data) => wsd.handle(data)
            }
            onConnectionStateChanged: {
                if (connected) {
                    write(JSON.stringify({ cmd: "subscribe" }) + "\n");
                } else {
                    // Демон закрыл соединение: сразу пробуем подключиться снова.
                    // Если он остановлен совсем, попытка не удастся, и следующая
                    // будет по событию от наблюдателя за сокетом.
                    wsd.desktops = {};
                    wsd.connect();
                }
            }
        }
    }

    // Демон заводит файл сокета заново при каждом запуске, и это событие —
    // повод подключиться. Прочитать сокет как файл нельзя, поэтому загрузка
    // всегда кончается ошибкой; нужен здесь только сигнал об изменении.
    property FileView socketWatcher: FileView {
        path: wsd.socketPath
        watchChanges: true
        printErrors: false
        onFileChanged: wsd.connect()
    }
    // Каталог сокета заводит сам демон, а наблюдатель за файлом в несуществующем
    // каталоге ничего не замечает. Если панель успела запуститься раньше демона,
    // о появлении каталога сообщит наблюдатель за $XDG_RUNTIME_DIR; тогда
    // наблюдатель за сокетом заводится заново вместе с попыткой подключиться.
    property FileView runtimeWatcher: FileView {
        path: wsd.runtimeDir
        watchChanges: true
        printErrors: false
        onFileChanged: {
            if (wsd.connected) return;
            wsd.socketWatcher.path = "";
            wsd.socketWatcher.path = wsd.socketPath;
            wsd.connect();
        }
    }

    Component.onCompleted: wsd.connect()
}
