// Переключатель раскладки (спецификация qs-tray-lang): код активной раскладки
// основной клавиатуры по событиям Hyprland activelayout, начальное состояние из
// `hyprctl devices -j`, клик переключает раскладку по кругу.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs

Tile {
    id: tile
    width: 36
    height: 36
    color: mouse.containsMouse ? Theme.background : Theme.tileBg

    property string keyboard: ""
    property string layout: "…"

    function code(name) {
        if (!name) return "…";
        if (name.indexOf("Russian") >= 0) return "RU";
        if (name.indexOf("English") >= 0) return "US";
        return name.substring(0, 2).toUpperCase();
    }

    Process {
        id: devices
        command: ["hyprctl", "devices", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    for (const k of d.keyboards) {
                        if (k.main) { tile.keyboard = k.name; tile.layout = tile.code(k.active_keymap); }
                    }
                } catch (e) { console.warn("lang: не разобран вывод hyprctl devices:", e); }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name !== "activelayout") return;
            const i = ev.data.indexOf(",");
            const kb = ev.data.substring(0, i);
            if (tile.keyboard === "" || kb === tile.keyboard) tile.layout = tile.code(ev.data.substring(i + 1));
        }
    }

    Text {
        anchors.centerIn: parent
        text: tile.layout
        color: Theme.yellow
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.Black
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onEntered: Popups.tooltip.show(tile, "Переключить раскладку")
        onExited: Popups.tooltip.hide()
        onClicked: {
            Popups.tooltip.hide();
            Run.detached(["hyprctl", "switchxkblayout", tile.keyboard || "all", "next"]);
        }
    }
}
