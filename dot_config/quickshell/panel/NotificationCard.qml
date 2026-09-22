// Карточка уведомления (спецификация qs-notifications, требования «Окно
// всплывающих уведомлений», «Действия и клики по уведомлению», «Значок,
// картинка и разметка тела», «Индикатор выполнения»). Оформление — как
// у плиток колонки: чёрная заливка 0.9, рамка 1 px, скругление 12 px,
// внутренний отступ 10 px до содержимого.
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: card
    required property var notification

    // Отступ до содержимого 10 px складывается из рамки и tilePadding.
    readonly property int pad: Theme.tilePadding + 1
    readonly property int iconSize: 48
    readonly property string icon: NotificationService.iconSource(card.notification)
    readonly property int progress: NotificationService.progress(card.notification)
    readonly property var buttons: NotificationService.buttons(card.notification)
    readonly property bool critical: card.notification.urgency === NotificationUrgency.Critical

    // Карточка уже растворяется; повторные просьбы закрыть её пропускаются.
    property bool closing: false
    // Действие, которое надо выполнить, когда растворение закончится.
    property var pendingAction: null
    // Закрыть по истечении (уйдёт в историю), а не как закрытое пользователем.
    property bool pendingExpire: false

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
            if (ev.button === Qt.MiddleButton) { NotificationService.closeAll(); return; }
            if (ev.button === Qt.RightButton) { NotificationService.requestClose(card.notification, null); return; }
            NotificationService.requestClose(card.notification,
                                             NotificationService.defaultAction(card.notification));
        }
    }

    // Растворение при закрытии: карточка становится прозрачной, и только
    // когда анимация закончилась, уведомление закрывается на самом деле.
    // Отсчёта времени в логике здесь нет — действие выполняет сигнал
    // окончания анимации.
    NumberAnimation {
        id: fade
        target: card
        property: "opacity"
        to: 0
        duration: 150
        easing.type: Easing.InQuad
        onFinished: card.finishClose()
    }

    Connections {
        target: NotificationService
        function onCloseRequested(n, action, expire) {
            if (n === card.notification) card.beginClose(action, expire);
        }
    }

    function beginClose(action, expire) {
        if (card.closing) return;
        card.closing = true;
        card.pendingAction = action;
        card.pendingExpire = expire === true;
        fade.start();
    }

    function finishClose() {
        const action = card.pendingAction;
        const expire = card.pendingExpire;
        card.pendingAction = null;
        // invoke() сообщает клиенту о выборе действия и закрывает уведомление
        // само, если клиент не просил оставить его открытым.
        if (action) action.invoke();
        else if (expire) card.notification.expire();
        else card.notification.dismiss();
        // Уведомление с признаком resident приложение просит оставить
        // открытым: после действия оно не закрывается, и карточка возвращается.
        if (NotificationService.shown.indexOf(card.notification) >= 0) {
            card.closing = false;
            card.pendingExpire = false;
            card.opacity = 1;
        }
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.pad
        spacing: Theme.gap

        Image {
            visible: card.icon !== ""
            Layout.preferredWidth: card.iconSize
            Layout.preferredHeight: card.iconSize
            Layout.alignment: Qt.AlignTop
            source: card.icon
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
                    text: card.notification.summary
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
                    text: card.notification.appName
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }
            }

            Text {
                visible: text !== ""
                Layout.fillWidth: true
                text: NotificationService.markup(card.notification.body)
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
                visible: card.progress >= 0
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 5
                radius: 2.5
                color: Theme.background
                Rectangle {
                    width: parent.width * card.progress / 100
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
                            onClicked: NotificationService.requestClose(card.notification, button.modelData)
                        }
                    }
                }
            }
        }
    }
}
