// Окно истории уведомлений (спецификация qs-notifications, требование «История
// уведомлений»): всплывающее окно панели справа от колонки с зазором 10 px,
// в оформлении плиток. Открывается кликом по плитке уведомлений и командой
// `qs -c panel ipc call notifications history`.
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import qs

PanelPopup {
    id: popup
    padX: 12
    padY: 8
    // Клавиатуру и монопольный захват указателя окно не просит: слой панели
    // фокуса не получает, и попытка захвата у композитора не удаётся, когда
    // окно открыто командой с клавиатуры, а не кликом. Поэтому закрывается
    // оно так же, как меню панели, — по уходу указателя.
    property bool entered: false

    // Плитка, к которой окно привязано: её задаёт плитка при создании окна.
    property Item anchorItem: null

    function open() {
        if (!popup.anchorItem) return;
        popup.entered = false;
        popup.target = popup.anchorItem;
        popup.anchor.updateAnchor();
        popup.visible = true;
        // Открытие истории обнуляет счётчик непрочитанных (design D5).
        NotificationService.markRead();
    }
    function close() { popup.visible = false; }
    function toggle() { if (popup.visible) popup.close(); else popup.open(); }

    onVisibleChanged: if (!visible) entered = false

    // Указатель считается ушедшим по наведению на всё окно целиком (свойство
    // hovered из PanelPopup), поэтому проход у самой рамки окно не закрывает.
    onHoveredChanged: {
        if (popup.hovered) popup.entered = true;
        else if (popup.entered) popup.close();
    }

    function stamp(time) {
        const h = String(time.getHours()).padStart(2, "0");
        const m = String(time.getMinutes()).padStart(2, "0");
        return h + ":" + m;
    }

    Item {
        id: box
        width: 560
        // Высота ограничена так, чтобы окно истории оставалось выше столбика
        // уведомлений и не пряталось под ним: столбик лежит на слое Overlay,
        // а всплывающее окно панели — ниже него.
        height: head.height + 9 + Math.max(28, Math.min(list.contentHeight, 640))

        Item {
            id: head
            width: parent.width
            height: 26

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "ИСТОРИЯ УВЕДОМЛЕНИЙ"
                color: Theme.gray
                font.family: Theme.fontFamily
                font.pointSize: Theme.pt(Theme.titleSize)
                font.bold: true
            }
            Rectangle {
                id: clear
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: clearLabel.implicitWidth + 20
                height: 24
                radius: 8
                color: clearMouse.containsMouse ? Theme.yellow : "transparent"
                border.color: Theme.yellow
                border.width: 1
                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "Очистить"
                    color: clearMouse.containsMouse ? "#000000" : Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: NotificationService.clearHistory()
                }
            }
        }

        Rectangle {
            id: separator
            y: head.height + 4
            width: parent.width
            height: 1
            color: Theme.yellow
        }

        Text {
            visible: NotificationService.history.length === 0
            y: separator.y + 9
            text: "Пропущенных уведомлений нет"
            color: Theme.gray
            font.family: Theme.fontFamily
            font.pixelSize: 16
        }

        ListView {
            id: list
            y: separator.y + 5
            width: parent.width
            height: box.height - y
            clip: true
            spacing: 6
            model: NotificationService.history

            delegate: Item {
                id: record
                required property var modelData
                required property int index
                width: list.width
                height: lines.implicitHeight + 8

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: recordMouse.containsMouse ? Theme.black : "transparent"
                }

                Row {
                    id: lines
                    x: 6
                    y: 4
                    width: parent.width - 12
                    spacing: Theme.gap

                    Image {
                        visible: record.modelData.icon !== ""
                        width: visible ? 20 : 0
                        height: 20
                        source: record.modelData.icon
                        sourceSize: Qt.size(40, 40)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Text {
                        width: 44
                        text: popup.stamp(record.modelData.time)
                        color: Theme.gray
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }
                    Column {
                        width: lines.width - lines.spacing * 2 - 44 - (record.modelData.icon !== "" ? 20 + lines.spacing : 0)
                        spacing: 2

                        Text {
                            width: parent.width
                            text: record.modelData.summary
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: record.modelData.urgency === NotificationUrgency.Critical ? Theme.red : Theme.yellow
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: NotificationService.markup(record.modelData.body)
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                    }
                }

                // Правый клик убирает одну запись.
                MouseArea {
                    id: recordMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.RightButton
                    onClicked: NotificationService.forget(record.index)
                }
            }
        }
    }
}
