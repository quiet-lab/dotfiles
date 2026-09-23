// Окно подсказки клавиш (спецификация qs-keys-help): перечень цепочек сессии,
// сгруппированный по назначению, в карточке шириной 1920 px по центру экрана
// в оформлении плиток. Перечень — одна колонка с прокруткой: колесо мыши,
// перетаскивание, стрелки, PageUp/PageDown, Home/End. Окно layer-shell на слое
// Overlay занимает экран целиком: клик мимо карточки закрывает окно, а на время
// показа слой берёт клавиатуру монопольно, чтобы закрыть окно клавишей Escape
// и прокручивать перечень клавишами. Привязки композитора при этом работают,
// поэтому повторное Shift+Super+/ тоже закрывает окно. Сроков показа нет.
// Данные и состояние — в синглтоне KeysHelp.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs

PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    // Размеры карточки и строк перечня.
    readonly property int cardWidth: 1920
    readonly property int padX: 24
    readonly property int padY: 18
    readonly property int rowHeight: 52
    readonly property int headHeight: 80
    readonly property int labelWidth: 580
    // Полоса у правого края под индикатор прокрутки.
    readonly property int barGap: 24

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    exclusiveZone: 0
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // Собственное пространство имён: правило размытия слоя panel сюда
    // не относится, иначе размывался бы весь экран.
    WlrLayershell.namespace: "keys-help"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: KeysHelp.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    color: "transparent"
    surfaceFormat.opaque: false
    visible: KeysHelp.shown

    // Затемнение экрана под карточкой; клик по нему закрывает окно.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: KeysHelp.hide()
        }
    }

    // Сдвиг прокрутки с ограничением пределами перечня.
    function scrollTo(y) {
        const max = Math.max(0, flick.contentHeight - flick.height);
        flick.contentY = Math.max(0, Math.min(max, y));
    }

    // Приёмник клавиш: слой держит клавиатуру, пока окно показано.
    Item {
        id: keys
        focus: true
        Keys.onPressed: (ev) => {
            const page = Math.max(win.rowHeight, flick.height - win.rowHeight);
            switch (ev.key) {
            case Qt.Key_Escape:
                KeysHelp.hide();
                break;
            case Qt.Key_Down:
                win.scrollTo(flick.contentY + win.rowHeight);
                break;
            case Qt.Key_Up:
                win.scrollTo(flick.contentY - win.rowHeight);
                break;
            case Qt.Key_PageDown:
                win.scrollTo(flick.contentY + page);
                break;
            case Qt.Key_PageUp:
                win.scrollTo(flick.contentY - page);
                break;
            case Qt.Key_Home:
                win.scrollTo(0);
                break;
            case Qt.Key_End:
                win.scrollTo(flick.contentHeight);
                break;
            default:
                return;
            }
            ev.accepted = true;
        }
    }
    // При каждом открытии перечень начинается сначала.
    onVisibleChanged: if (visible) {
        flick.cancelFlick();
        flick.contentY = 0;
        keys.forceActiveFocus();
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.margin
        width: win.cardWidth
        height: parent.height - 2 * Theme.margin
        color: Theme.tileBg
        border.color: Theme.tileBorder
        border.width: 1
        radius: Theme.tileRadius

        // Клики по карточке окно не закрывают.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        // Шапка: заголовок, напоминание о закрытии, черта и сообщения
        // о загрузке; не прокручивается.
        Column {
            id: head
            x: win.padX
            y: win.padY
            width: card.width - 2 * win.padX
            spacing: 8

            Item {
                width: parent.width
                height: 56

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ГОРЯЧИЕ КЛАВИШИ"
                    color: Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: 36
                    font.bold: true
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Shift+Super+/ или Escape — закрыть"
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: 30
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.yellow
            }

            // Ошибка загрузки: конфиг с ошибкой или бинарник демона без --json.
            Text {
                visible: KeysHelp.error !== ""
                width: parent.width
                text: "Перечень клавиш не получен:\n" + KeysHelp.error
                wrapMode: Text.Wrap
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: 32
            }
            Text {
                visible: KeysHelp.loading && KeysHelp.groups.length === 0
                text: "Загрузка…"
                color: Theme.gray
                font.family: Theme.fontFamily
                font.pixelSize: 32
            }
        }

        // Перечень одной колонкой с прокруткой. Колесо и перетаскивание
        // обрабатывает сам Flickable, клавиши — приёмник keys выше.
        Flickable {
            id: flick
            x: win.padX
            y: head.y + head.height
            width: card.width - 2 * win.padX
            height: card.height - y - win.padY
            clip: true
            contentWidth: width
            contentHeight: list.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: flick.width - win.barGap
                spacing: 0

                Repeater {
                    model: KeysHelp.groups

                    Column {
                        id: group
                        required property var modelData
                        width: list.width

                        Item {
                            width: parent.width
                            height: win.headHeight
                            Text {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 12
                                text: group.modelData.name.toUpperCase()
                                color: Theme.gray
                                font.family: Theme.fontFamily
                                font.pointSize: Theme.pt(Theme.titleSize * 2)
                                font.bold: true
                            }
                        }

                        Repeater {
                            model: group.modelData.keys

                            Item {
                                id: row
                                required property var modelData
                                width: group.width
                                height: win.rowHeight

                                Text {
                                    width: win.labelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label
                                    elide: Text.ElideRight
                                    color: Theme.yellow
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 32
                                }
                                Text {
                                    x: win.labelWidth + 24
                                    width: parent.width - x
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.desc
                                    elide: Text.ElideRight
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 32
                                }
                            }
                        }
                    }
                }
            }
        }

        // Индикатор прокрутки у правого края перечня: показывает видимую
        // часть; виден, только когда перечень выше области прокрутки.
        Rectangle {
            visible: flick.contentHeight > flick.height
            x: flick.x + flick.width - width
            y: flick.y + flick.visibleArea.yPosition * flick.height
            width: 6
            height: flick.visibleArea.heightRatio * flick.height
            radius: 3
            color: Theme.gray
        }
    }
}
