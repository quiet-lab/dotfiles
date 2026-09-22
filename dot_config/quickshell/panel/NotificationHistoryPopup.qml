// Окно истории уведомлений (спецификация qs-notifications, требование
// «История уведомлений»): всплывающее окно панели справа от колонки
// с зазором 10 px, в оформлении плиток. Показывает все записи за сутки,
// новые сверху, и отличает просмотренные от непросмотренных. Левый клик
// по записи переключает её состояние, правый выполняет действие по умолчанию
// и удаляет запись. Открывается кликом по плитке и командой
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
        // Обращение к истории — повод отбросить записи старше суток.
        NotificationService.prune();
        popup.entered = false;
        popup.target = popup.anchorItem;
        popup.anchor.updateAnchor();
        popup.visible = true;
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
        const d = new Date(time);
        const h = String(d.getHours()).padStart(2, "0");
        const m = String(d.getMinutes()).padStart(2, "0");
        return h + ":" + m;
    }

    Item {
        id: box
        width: 560
        // Высота ограничена так, чтобы окно, открытое от плитки на уровне
        // первого стола, умещалось до нижнего края экрана: столбик уведомлений
        // лежит на слое Overlay, а всплывающее окно панели — ниже него, и
        // выросшее окно пряталось бы под карточками.
        height: head.height + 9 + Math.max(28, Math.min(list.contentHeight, 620))

        Item {
            id: head
            width: parent.width
            height: 26

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "УВЕДОМЛЕНИЯ ЗА СУТКИ"
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
            visible: NotificationService.records.length === 0
            y: separator.y + 9
            text: "Уведомлений за сутки нет"
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
            model: NotificationService.newestFirst

            delegate: Item {
                id: row
                required property var modelData
                readonly property bool seen: row.modelData.seen
                // Действие по умолчанию есть только у записи с живым
                // уведомлением: после перезапуска панели объекты потеряны.
                readonly property bool actionable: NotificationService.defaultAction(row.modelData.notification) !== null
                width: list.width
                height: lines.implicitHeight + 8

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: rowMouse.containsMouse ? Theme.black : "transparent"
                }

                // Метка состояния: непросмотренная запись отмечена точкой
                // цвета рамки, просмотренная — пустым кружком.
                Rectangle {
                    x: 4
                    y: 10
                    width: 8
                    height: 8
                    radius: 4
                    color: row.seen ? "transparent" : Theme.yellow
                    border.color: Theme.gray
                    border.width: row.seen ? 1 : 0
                }

                Row {
                    id: lines
                    x: 18
                    y: 4
                    width: parent.width - 24
                    spacing: Theme.gap

                    Image {
                        visible: row.modelData.icon !== ""
                        width: visible ? 20 : 0
                        height: 20
                        source: row.modelData.icon
                        sourceSize: Qt.size(40, 40)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        opacity: row.seen ? 0.5 : 1
                    }
                    Text {
                        width: 44
                        text: popup.stamp(row.modelData.time)
                        color: Theme.gray
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                    }
                    Column {
                        width: lines.width - lines.spacing * 2 - 44
                               - (row.modelData.icon !== "" ? 20 + lines.spacing : 0)
                        spacing: 2

                        Text {
                            width: parent.width
                            // Запись без действия по умолчанию (уведомление
                            // закрыто приложением или потеряно при перезапуске
                            // панели) не выделяется подчёркиванием.
                            text: row.actionable ? "<u>" + row.modelData.summary + "</u>"
                                                 : row.modelData.summary
                            textFormat: Text.StyledText
                            elide: Text.ElideRight
                            color: row.seen ? Theme.gray
                                            : (row.modelData.urgency === NotificationUrgency.Critical
                                               ? Theme.red : Theme.yellow)
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            font.bold: !row.seen
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            text: NotificationService.markup(row.modelData.body)
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            color: row.seen ? Theme.gray : Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                        }
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (ev) => {
                        if (ev.button === Qt.RightButton) NotificationService.requestAct(row.modelData);
                        else NotificationService.toggleSeen(row.modelData);
                    }
                }
            }
        }
    }
}
