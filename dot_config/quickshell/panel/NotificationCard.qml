// Карточка уведомления на экране (спецификация qs-notifications). Рисует
// запись истории: значок, заголовок, тело с разметкой, полосу по подсказке
// `value` и кнопки действий. Клики: левый — пометить просмотренным и убрать
// с экрана, правый — действие по умолчанию и удаление из истории, средний —
// пометить просмотренными все. Карточку создаёт и расставляет
// NotificationStack.qml, она же растворяется при уходе.
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import qs
import qs.common

Rectangle {
    id: card
    // Запись истории, которую показывает карточка.
    required property var record

    // Отступ до содержимого 10 px складывается из рамки и tilePadding.
    readonly property int pad: Theme.tilePadding + 1
    readonly property int iconSize: 48
    readonly property var notification: card.record.notification
    readonly property var buttons: NotificationService.buttons(card.notification)
    readonly property bool critical: card.record.urgency === NotificationUrgency.Critical

    // Карточка уже растворяется; повторные просьбы пропускаются.
    property bool closing: false
    // Что сделать, когда растворение кончится: "seen", "seenAct", "act" или
    // пусто — просто исчезнуть (карточку убрали не действием пользователя).
    property string pendingKind: ""

    // Смещение верхнего края карточки от нижнего края окна столбика.
    // Расстановку задаёт столбик, а едет к ней карточка сама, поэтому
    // появление снизу, подъём и опускание — одна и та же анимация положения.
    property int moveDuration: 200
    property real targetOffset: 0
    property real offset: 0
    Behavior on offset {
        NumberAnimation { duration: card.moveDuration; easing.type: Easing.OutQuad }
    }
    onTargetOffsetChanged: card.offset = card.targetOffset

    implicitHeight: row.implicitHeight + 2 * card.pad
    color: Theme.tileBg
    border.color: card.critical ? Theme.red : Theme.tileBorder
    border.width: 1
    radius: Theme.tileRadius

    // Клики по карточке. Область объявлена раньше содержимого, поэтому кнопки
    // действий лежат над ней и забирают свои клики себе.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: (ev) => {
            if (ev.button === Qt.MiddleButton) { NotificationService.markAllSeen(); return; }
            if (ev.button === Qt.RightButton) { NotificationService.requestAct(card.record); return; }
            NotificationService.requestSeenAction(card.record);
        }
    }

    // Растворение: карточка становится прозрачной, и только когда анимация
    // закончилась, меняется состояние записи. Отсчёта времени в логике нет —
    // действие выполняет сигнал окончания анимации.
    NumberAnimation {
        id: fade
        target: card
        property: "opacity"
        to: 0
        duration: 150
        easing.type: Easing.InQuad
        onFinished: card.finished()
    }

    Connections {
        target: NotificationService
        function onCardActionRequested(rec, kind) {
            if (rec === card.record) card.fadeThen(kind);
        }
    }

    function fadeThen(kind) {
        if (card.closing) return;
        card.closing = true;
        card.pendingKind = kind;
        fade.start();
    }

    // Запись ушла с экрана не по клику (режим «не беспокоить», удаление
    // из истории, истёкший срок): карточку надо просто убрать.
    function vanish() {
        if (card.closing) { card.destroy(); return; }
        card.closing = true;
        card.pendingKind = "";
        fade.start();
    }

    function finished() {
        const kind = card.pendingKind;
        card.pendingKind = "";
        if (kind === "seen") NotificationService.markSeen(card.record);
        else if (kind === "seenAct") NotificationService.seenWithAction(card.record);
        else if (kind === "act") NotificationService.act(card.record);
        else card.destroy();
        // После смены состояния запись уходит с экрана, и столбик уничтожит
        // карточку сам.
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.pad
        spacing: Theme.gap

        Image {
            visible: card.record.icon !== ""
            Layout.preferredWidth: card.iconSize
            Layout.preferredHeight: card.iconSize
            Layout.alignment: Qt.AlignTop
            source: card.record.icon
            sourceSize: Qt.size(card.iconSize * 2, card.iconSize * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                Text {
                    Layout.fillWidth: true
                    text: card.record.summary
                    // Заголовок выводится без разметки: спецификация уведомлений
                    // разрешает её только в теле.
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: card.critical ? Theme.red : Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    visible: text !== ""
                    Layout.alignment: Qt.AlignTop
                    text: card.record.appName
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }
            }

            Text {
                visible: text !== ""
                Layout.fillWidth: true
                text: NotificationService.markup(card.record.body)
                // Безопасное подмножество разметки: StyledText не ходит в сеть
                // и не открывает ссылок, неизвестные теги отбрасывает (design D10).
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 15
            }

            // Полоса заполнения по подсказке value.
            Rectangle {
                visible: card.record.progress >= 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 5
                radius: 2.5
                color: Theme.background
                Rectangle {
                    width: parent.width * Math.max(0, card.record.progress) / 100
                    height: parent.height
                    radius: parent.radius
                    color: Theme.yellow
                }
            }

            // Кнопки действий.
            Flow {
                visible: card.buttons.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6
                Repeater {
                    model: card.buttons
                    delegate: Rectangle {
                        id: button
                        required property var modelData
                        implicitWidth: label.implicitWidth + 20
                        implicitHeight: label.implicitHeight + 8
                        radius: 8
                        color: buttonMouse.containsMouse ? Theme.yellow : "transparent"
                        border.color: Theme.yellow
                        border.width: 1
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: button.modelData.text
                            color: buttonMouse.containsMouse ? "#000000" : Theme.yellow
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            font.bold: true
                        }
                        MouseArea {
                            id: buttonMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                button.modelData.invoke();
                                NotificationService.requestSeen(card.record);
                            }
                        }
                    }
                }
            }
        }
    }
}
