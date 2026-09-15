// Плитка избранного (спецификация qs-shell): три кнопки, каждая открывает yazi
// в wezterm (конфиг apps.lua, класс окна yazi) в своём каталоге.
import Quickshell
import QtQuick
import qs

Tile {
    id: tile
    height: 123
    title: "ИЗБРАННОЕ"

    readonly property var entries: [
        { label: "󰉋 ~",          dir: Quickshell.env("HOME") },
        { label: "󰉋 ~/Загрузки", dir: Quickshell.env("HOME") + "/Загрузки" },
        { label: "󰉋 ~/.config",  dir: Quickshell.env("HOME") + "/.config" }
    ]

    Column {
        Repeater {
            model: tile.entries
            Rectangle {
                id: btn
                required property var modelData
                width: label.implicitWidth + 12
                height: label.implicitHeight + 8
                radius: 6
                color: mouse.containsMouse ? Theme.background : "transparent"

                Text {
                    id: label
                    x: 6; y: 4
                    text: btn.modelData.label
                    color: mouse.containsMouse ? Theme.magenta : Theme.cyan
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Run.detached([
                        "wezterm", "--config-file", Quickshell.env("HOME") + "/.config/wezterm/apps.lua",
                        "start", "--class", "yazi", "--cwd", btn.modelData.dir, "--", "yazi"
                    ])
                }
            }
        }
    }
}
