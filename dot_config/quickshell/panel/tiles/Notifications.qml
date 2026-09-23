// Плитка уведомлений (спецификация qs-notifications, требование «Плитка
// уведомлений»): маленький виджет 36×36 в одной колонке с треем и
// переключателем раскладки, на уровне плитки первого рабочего стола.
// Показывает глиф колокольчика, а при непросмотренных уведомлениях — их число
// в кружке поверх глифа. Левый клик открывает и закрывает окно истории,
// правый переключает режим «не беспокоить».
import Quickshell
import QtQuick
import qs
import qs.common

Tile {
    id: tile
    width: 36
    height: 36
    color: mouse.containsMouse ? Theme.background : Theme.tileBg

    readonly property bool dnd: NotificationService.dnd
    readonly property int records: NotificationService.unseen

    Text {
        anchors.centerIn: parent
        text: tile.dnd ? "󰂛" : "󰂚"
        color: tile.dnd ? Theme.gray : Theme.yellow
        font.family: Theme.fontFamily
        font.pixelSize: 20
    }

    // Счётчик непросмотренных уведомлений в правом верхнем углу плитки.
    // Содержимое плитки
    // лежит с отступом 10 px от края, поэтому кружок вынесен за его границы
    // отрицательными полями.
    Rectangle {
        visible: tile.records > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -6
        anchors.topMargin: -6
        width: Math.max(16, badge.implicitWidth + 6)
        height: 16
        radius: 8
        color: Theme.yellow
        Text {
            id: badge
            anchors.centerIn: parent
            text: tile.records
            color: "#000000"
            font.family: Theme.fontFamily
            font.pixelSize: 11
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
