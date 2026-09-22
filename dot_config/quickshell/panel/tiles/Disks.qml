// Плитка дисков (спецификация qs-monitors): строки блочных устройств из
// scripts/disks (JSON-массив) с полосами заполнения, обновление раз в 30 с.
import Quickshell
import Quickshell.Io
import QtQuick
import qs

Tile {
    id: tile
    height: 235
    title: "ДИСКИ"
    clip: true

    property var disks: []

    Process {
        id: proc
        command: [Quickshell.shellDir + "/scripts/disks"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { tile.disks = JSON.parse(text); } catch (e) { console.warn("disks: не JSON:", text); }
            }
        }
    }
    // WARNING: опрос по таймеру, событий не существует. Занятое и свободное место
    // ядро сообщает только в ответ на запрос (statfs, его и делает df в
    // scripts/disks); уведомления о том, что файловая система заполнилась, нет.
    // Опрашивается список устройств с их заполнением раз в 30 с: свободное место
    // меняется плавно, и более частый запуск скрипта ничего не добавит. Граница:
    // появление и исчезновение дисков, монтирование и размонтирование приходят
    // событиями udev, и когда плитка на них подпишется, таймер останется только
    // за заполнением. Решение записано в docs/decisions/0007-no-timers.md.
    Timer { interval: 30000; running: true; repeat: true; onTriggered: proc.running = true }

    Column {
        width: parent.width
        Repeater {
            model: tile.disks
            Item {
                id: row
                required property var modelData
                width: parent.width
                height: 6 + Math.max(name.implicitHeight, 10)

                Text {
                    id: name
                    y: 6
                    width: 70
                    text: row.modelData.name
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    elide: Text.ElideRight
                }
                // Смонтированный: полоса заполнения и свободное место.
                Rectangle {
                    visible: row.modelData.mounted
                    x: name.width + 8
                    width: parent.width - name.width - 8 - 8 - free.width
                    height: 10
                    anchors.verticalCenter: name.verticalCenter
                    radius: 5
                    color: Theme.background
                    Rectangle {
                        width: parent.width * Math.min(100, row.modelData.percent) / 100
                        height: parent.height
                        radius: 5
                        color: Theme.blue
                    }
                }
                Text {
                    id: free
                    visible: row.modelData.mounted
                    anchors.right: parent.right
                    y: 6
                    width: Math.max(55, implicitWidth)
                    horizontalAlignment: Text.AlignRight
                    text: row.modelData.free
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                // Несмонтированный: тип файловой системы справа.
                Text {
                    visible: !row.modelData.mounted
                    anchors.right: parent.right
                    anchors.verticalCenter: name.verticalCenter
                    text: row.modelData.fstype
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.pt(12.6)
                }
            }
        }
    }
}
