// Плитки питания (спецификация qs-shell, требование «Плитка питания»): пять
// квадратов 56×56 в один ряд. Размеры глифов и смещения подобраны в eww
// (power.scss): большая сторона глифа 44 px, наименьший зазор до рамки 5 px.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs

Item {
    id: root
    width: Theme.tileWidth
    height: 56

    // Смещения глифа: половина разности отступов eww (сверху, справа, снизу, слева).
    // Размер (font.pixelSize) и смещение глифа (dx, dy) подобраны по замеру снимка
    // (scratchpad/measure-power.py): замок и выход высотой ~32 px по центру; у трёх
    // круглых глифов наружный диаметр кольца 35 px, как у глифа выключения, с центром в центре плитки — стрелки
    // перезапуска (сверху) и перезагрузки (справа) в центровке не участвуют.
    readonly property var buttons: [
        { icon: "󰌾", size: 37, dx: 0, dy: 1, hover: "#ffffff", tip: "Lock Screen",
          run: () => Run.detached(["loginctl", "lock-session"]) },
        { icon: "󰗽", size: 43, dx: -0.5, dy: 0.5, hover: "#2244ff", tip: "Logout",
          run: () => Hyprland.dispatch("hl.dsp.exit()") },
        { icon: "󰜉", size: 54, dx: 0, dy: -3.4, hover: "#006600", tip: "Hyprland Reload",
          run: () => Run.detached(["hyprctl", "reload"]) },
        { icon: "󰑓", size: 48, dx: 2.7, dy: 0, hover: "#ff6600", tip: "Reboot",
          run: () => Run.detached(["systemctl", "reboot"]) },
        { icon: "󰐥", size: 53, dx: 0.5, dy: 0, hover: "#dd0000", tip: "Shutdown",
          run: () => Run.detached(["systemctl", "poweroff"]) }
    ]

    Repeater {
        model: root.buttons
        Tile {
            id: btn
            required property var modelData
            required property int index
            x: index * 66
            width: 56
            height: 56
            color: mouse.containsMouse ? modelData.hover : Theme.tileBg
            border.color: mouse.containsMouse ? modelData.hover : Theme.tileBorder
            clip: true

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: btn.modelData.dx
                anchors.verticalCenterOffset: btn.modelData.dy
                text: btn.modelData.icon
                color: mouse.containsMouse ? "#000000" : Theme.yellow
                font.family: Theme.fontFamily
                font.pixelSize: btn.modelData.size
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onEntered: Popups.tooltip.show(btn, btn.modelData.tip)
                onExited: Popups.tooltip.hide(btn)
                onClicked: { Popups.tooltip.hide(btn); btn.modelData.run(); }
            }
        }
    }
}
