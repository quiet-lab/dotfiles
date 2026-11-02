// Окно состояния и настроек туннеля (спецификация qs-tray-lang, требование
// «Значки туннелей»): заголовок, строки «подпись — значение», последние строки
// журнала и кнопки действий. Содержимое читается один раз при открытии
// (scripts/tunnelinfo), окно само его не обновляет. Оформление — как у меню
// трея: заливка и рамка плиток, жёлтые подписи. Закрывается кликом вне окна
// и после нажатия кнопки.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.common

PanelPopup {
    id: popup
    padX: 12
    padY: 10
    grabFocus: true

    property string title: ""
    // [[подпись, значение], …], строки журнала и кнопки { label, action }.
    property var rows: []
    property var log: []
    property var actions: []
    // Число столбцов кнопок: одна строка по умолчанию, сетка для списка стран.
    property int columns: 0

    // grab: false — окно без захвата ввода (открытие по IPC для проверки:
    // захват требует, чтобы панель только что получила клик, иначе Wayland
    // отказывает в окне).
    function open(item, heading, info, buttons, grab, cols) {
        popup.grabFocus = grab !== false;
        popup.columns = cols || 0;
        popup.title = heading;
        popup.rows = info.rows || [];
        popup.log = info.log || [];
        popup.actions = buttons;
        popup.target = item;
        popup.anchor.updateAnchor();
        popup.visible = true;
    }
    function close() { popup.visible = false; }

    ColumnLayout {
        spacing: 6

        Text {
            text: popup.title
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.bold: true
        }
        GridLayout {
            columns: 2
            columnSpacing: 14
            rowSpacing: 2
            Repeater {
                model: popup.rows.length * 2
                Text {
                    required property int index
                    readonly property var pair: popup.rows[Math.floor(index / 2)]
                    text: pair[index % 2]
                    color: index % 2 === 0 ? Theme.gray : Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                }
            }
        }
        Rectangle {
            visible: popup.log.length > 0
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.yellow
        }
        Repeater {
            model: popup.log
            Text {
                required property string modelData
                text: modelData
                color: Theme.gray
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }
        // Кнопки действий в ряд (или сеткой): подпись жёлтая, при наведении —
        // чёрная на жёлтом; отмеченная кнопка (current) залита жёлтым.
        GridLayout {
            columns: popup.columns > 0 ? popup.columns : Math.max(1, popup.actions.length)
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: popup.actions
                Rectangle {
                    id: btn
                    required property var modelData
                    readonly property bool marked: modelData.current === true
                    Layout.fillWidth: popup.columns > 0
                    implicitWidth: label.implicitWidth + 20
                    implicitHeight: label.implicitHeight + 8
                    radius: 6
                    color: mouse.containsMouse || marked ? Theme.yellow : "transparent"
                    border.color: Theme.yellow
                    border.width: 1
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: btn.modelData.label
                        color: mouse.containsMouse || btn.marked ? "#000000" : Theme.yellow
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { popup.close(); btn.modelData.action(); }
                    }
                }
            }
        }
    }
}
