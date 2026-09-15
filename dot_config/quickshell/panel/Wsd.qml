// Связь с демоном workspaced (спецификация ws-daemon, «Состояние для панели»;
// design D12 изменения workspace-daemon): подписка по сокету
// $XDG_RUNTIME_DIR/workspaced/sock, строки JSON. Состояние столов приходит
// целиком при подключении и после каждого изменения; событие show-sessions
// открывает окно выбора сессии. Без демона панель показывает только окна и
// пробует подключиться раз в 5 секунд.
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
    id: wsd

    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/workspaced/sock"
    property bool connected: socket.connected
    // Номер стола → { workspaces: [{ name, icon, active, apps, windows }], active }.
    property var desktops: ({})
    property int currentDesktop: 0
    // Последний список сессий (от show-sessions или ответа session list).
    property var sessions: []
    signal showSessions(var list)

    function send(obj) {
        if (!socket.connected) return;
        socket.write(JSON.stringify(obj) + "\n");
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

    property Socket socket: Socket {
        path: wsd.socketPath
        connected: true
        parser: SplitParser {
            splitMarker: "\n"
            onRead: (data) => wsd.handle(data)
        }
        onConnectedChanged: {
            if (connected) socket.write(JSON.stringify({ cmd: "subscribe" }) + "\n");
            else wsd.desktops = {};
        }
    }
    // Переподключение, пока демона нет.
    property Timer reconnect: Timer {
        interval: 5000
        repeat: true
        running: !wsd.socket.connected
        onTriggered: { wsd.socket.connected = false; wsd.socket.connected = true; }
    }
}
