// Плитка уведомлений (спецификация qs-notifications, требование «Плитка
// уведомлений»): глиф колокольчика, подпись состояния и счётчик записей,
// попавших в историю с последнего её открытия. Левый клик открывает и
// закрывает окно истории, правый переключает режим «не беспокоить».
import Quickshell
import QtQuick
import qs

Tile {
    id: tile
    height: 36
    color: mouse.containsMouse ? Theme.background : Theme.tileBg

    readonly property bool dnd: NotificationService.dnd
    readonly property int unread: NotificationService.unread

    Text {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        text: tile.dnd ? "󰂛" : "󰂚"
        color: tile.dnd ? Theme.gray : Theme.yellow
        font.family: Theme.fontFamily
        font.pixelSize: 20
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        x: glyph.width + Theme.gap
        text: tile.dnd ? "Не беспокоить" : "Уведомления"
        color: tile.dnd ? Theme.gray : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // Счётчик непрочитанных; нулевой не показывается.
    Rectangle {
        id: badge
        visible: tile.unread > 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: Math.max(22, count.implicitWidth + 12)
        height: 20
        radius: 10
        color: Theme.yellow
        Text {
            id: count
            anchors.centerIn: parent
            text: tile.unread
            color: "#000000"
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.bold: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: Popups.tooltip.show(tile, "ЛКМ — история, ПКМ — не беспокоить")
        onExited: Popups.tooltip.hide(tile)
        onClicked: (ev) => {
            Popups.tooltip.hide(tile);
            if (ev.button === Qt.RightButton) NotificationService.toggleDnd();
            else history.toggle();
        }
    }

    NotificationHistoryPopup { id: history; anchorItem: tile }

    // Окно истории открывается и командой с клавиатуры
    // (qs -c panel ipc call notifications history).
    Connections {
        target: NotificationService
        function onHistoryToggleRequested() { history.toggle(); }
    }
}
