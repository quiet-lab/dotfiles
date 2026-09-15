// Всплывающее меню панели (меню окна, меню сети): список пунктов в стиле плиток.
// Пункт: { label, action, enabled, separator }. Закрывается после выбора пункта,
// кликом вне меню и когда указатель покидает его (после того, как побывал в нём).
import Quickshell
import QtQuick
import QtQuick.Layouts

PanelPopup {
    id: menu
    padX: 6
    padY: 6
    grabFocus: true

    property var items: []
    // Указатель уже побывал в меню: с этого момента уход закрывает его.
    property bool entered: false

    function open(item, list) {
        menu.items = list;
        menu.entered = false;
        menu.target = item;
        menu.anchor.updateAnchor();
        menu.visible = true;
    }
    function close() { menu.visible = false; }

    onVisibleChanged: if (!visible) { entered = false; leaveTimer.stop(); }

    Timer {
        id: leaveTimer
        interval: 300
        onTriggered: if (!hover.hovered) menu.close()
    }

    ColumnLayout {
        id: list
        spacing: 0

        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered) { menu.entered = true; leaveTimer.stop(); }
                else if (menu.entered) leaveTimer.restart();
            }
        }

        Repeater {
            model: menu.items
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool sep: modelData.separator === true
                readonly property bool enabled: modelData.enabled !== false
                Layout.fillWidth: true
                implicitWidth: sep ? 0 : label.implicitWidth + 24
                implicitHeight: sep ? 9 : label.implicitHeight + 10

                Rectangle {
                    visible: row.sep
                    x: 6; y: 4
                    width: parent.width - 12; height: 1
                    color: Theme.yellow
                }
                Rectangle {
                    visible: !row.sep
                    anchors.fill: parent
                    radius: 8
                    color: mouse.containsMouse && row.enabled ? Theme.yellow : "transparent"
                    Text {
                        id: label
                        x: 12; y: 5
                        text: row.modelData.label || ""
                        color: !row.enabled ? Theme.gray : mouse.containsMouse ? "#000000" : Theme.yellow
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.enabled
                        onClicked: { menu.close(); if (row.modelData.action) row.modelData.action(); }
                    }
                }
            }
        }
    }
}
