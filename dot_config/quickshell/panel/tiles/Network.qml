// Плитка сети (спецификация qs-network, design D8): строки ETH, WIFI, VPN из
// scripts/netstate, перечитываемого только по событиям NetworkManager (поток
// nmcli monitor); клик по телу — nm-connection-editor, кнопка «⋮» — меню
// действий, содержимое которого строит scripts/netmenu при каждом открытии.
import Quickshell
import Quickshell.Io
import QtQuick
import qs
import qs.common

Tile {
    id: tile
    height: 107
    title: "СЕТЬ"

    property var state: ({ eth: { connected: false, ip: "" }, wifi: { connected: false, ip: "" }, vpn: "" })

    // Строка от nmcli monitor пришла во время чтения состояния: прочитать ещё раз,
    // когда текущее чтение закончится, иначе последнее изменение будет потеряно.
    property bool statePending: false
    // Когда монитор запущен и сколько раз подряд он вышел сразу после запуска.
    property double monitorStarted: 0
    property int monitorFailures: 0
    function readState() {
        if (stateProc.running) { tile.statePending = true; return; }
        stateProc.running = true;
    }

    Process {
        id: stateProc
        command: [Quickshell.shellDir + "/scripts/netstate"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { tile.state = JSON.parse(text); } catch (e) { console.warn("network: не JSON:", text); }
            }
        }
        onExited: if (tile.statePending) { tile.statePending = false; stateProc.running = true; }
    }
    // Поток событий NetworkManager: каждая строка — изменение, по ней состояние
    // и перечитывается.
    Process {
        id: monitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: tile.readState()
        }
        onRunningChanged: if (running) tile.monitorStarted = Date.now()
        onExited: {
            // Монитор заканчивается, когда перезапускается NetworkManager: тем же
            // событием он и поднимается заново. Счёт подряд идущих мгновенных
            // выходов нужен на случай, когда nmcli не запускается вовсе (нет
            // NetworkManager, нет прав): иначе выход и запуск пошли бы по кругу.
            if (Date.now() - tile.monitorStarted >= 1000) tile.monitorFailures = 0;
            else tile.monitorFailures++;
            if (tile.monitorFailures < 5) monitor.running = true;
            else console.warn("network: nmcli monitor не запускается, состояние сети больше не обновляется");
        }
    }

    // --- Кнопка меню в заголовке ---
    Text {
        id: menuBtn
        // Кнопка живёт в самой плитке, а не во внутренней области под заголовком:
        // она стоит в строке заголовка у правой рамки.
        parent: tile
        anchors.right: parent.right
        anchors.rightMargin: Theme.tilePadding + 1
        y: 5
        text: "⋮"
        color: menuMouse.containsMouse ? Theme.cyan : Theme.gray
        font.family: Theme.fontFamily
        font.pointSize: Theme.pt(16.8)
        MouseArea {
            id: menuMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            onEntered: Popups.tooltip.show(menuBtn, "Действия сети")
            onExited: Popups.tooltip.hide(menuBtn)
            onClicked: {
                Popups.tooltip.hide(menuBtn);
                if (Popups.menu.visible && Popups.menu.target === menuBtn) Popups.menu.close();
                else menuProc.running = true;
            }
        }
    }
    Process {
        id: menuProc
        command: [Quickshell.shellDir + "/scripts/netmenu"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { Popups.menu.open(menuBtn, tile.menuItems(JSON.parse(text))); } catch (e) { console.warn("netmenu: не JSON:", text); }
            }
        }
    }
    function run(args) { Run.detached(args); }
    function menuItems(m) {
        const items = [];
        if (m.wifi) {
            items.push({ label: "Поиск сетей Wi-Fi", action: () => run(["nmcli", "device", "wifi", "rescan"]) });
            items.push({ label: "Выключить Wi-Fi", action: () => run(["nmcli", "radio", "wifi", "off"]) });
        } else {
            items.push({ label: "Включить Wi-Fi", action: () => run(["nmcli", "radio", "wifi", "on"]) });
        }
        for (const v of m.vpns) {
            if (v.active) items.push({ label: "Отключить " + v.name, action: () => run(["nmcli", "con", "down", "id", v.name]) });
            else items.push({ label: "Подключить " + v.name, action: () => run(["nmcli", "con", "up", "id", v.name]) });
        }
        if (m.eth) items.push({ label: "Отключить " + m.eth, action: () => run(["nmcli", "device", "disconnect", m.eth]) });
        return items;
    }

    // --- Строки состояния ---
    readonly property var rows: [
        { icon: "󰈀", on: state.eth.connected,  text: state.eth.connected ? "ETH " + state.eth.ip : "ETH отключено" },
        { icon: state.wifi.connected ? "󰤨" : "󰤮", on: state.wifi.connected, text: state.wifi.connected ? "WIFI " + state.wifi.ip : "WIFI отключено" },
        { icon: "󰦝", on: state.vpn !== "", text: state.vpn !== "" ? "VPN " + state.vpn : "VPN отключено" }
    ]
    Column {
        width: parent.width
        Repeater {
            model: tile.rows
            Item {
                id: row
                required property var modelData
                width: parent.width
                // Строка 22 px (4 px зазор + 18 px глифа), как в плитке eww высотой 107 px.
                height: 22
                Text {
                    id: icon
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 2
                    text: row.modelData.icon
                    color: row.modelData.on ? Theme.green : Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                }
                Text {
                    id: label
                    x: icon.width + 10
                    anchors.verticalCenter: icon.verticalCenter
                    text: row.modelData.text
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.pt(14.7)
                }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        anchors.topMargin: 30
        hoverEnabled: true
        onEntered: Popups.tooltip.show(tile, "ЛКМ — редактор соединений")
        onExited: Popups.tooltip.hide(tile)
        onClicked: { Popups.tooltip.hide(tile); Run.detached(["nm-connection-editor"]); }
    }
}
