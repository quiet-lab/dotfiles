// Окно подсказки клавиш (спецификация qs-keys-help): перечень цепочек сессии,
// сгруппированный по назначению, в карточке по центру экрана в оформлении
// плиток. Окно layer-shell на слое Overlay занимает экран целиком: клик мимо
// карточки закрывает окно, а на время показа слой берёт клавиатуру монопольно,
// чтобы закрыть окно клавишей Escape. Привязки композитора при этом работают,
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

    // Колонки карточки: группы раскладываются по ним по порядку, каждая
    // следующая колонка начинается, когда предыдущая набрала свою долю строк.
    readonly property int columns: 3
    readonly property int columnWidth: 800
    readonly property int rowHeight: 26
    readonly property int headHeight: 40
    readonly property int labelWidth: 290

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

    // Группы по колонкам: [[группа, …], …]. Доля колонки считается в строках,
    // заголовок группы весит как полторы строки.
    readonly property var layout: {
        const groups = KeysHelp.groups;
        const weight = g => 1.5 + (g.keys || []).length;
        let total = 0;
        for (const g of groups) total += weight(g);
        const cols = [];
        let cur = [];
        let acc = 0;
        for (const g of groups) {
            const w = weight(g);
            if (cur.length > 0 && cols.length < win.columns - 1
                    && acc + w / 2 > total * (cols.length + 1) / win.columns) {
                cols.push(cur);
                cur = [];
            }
            cur.push(g);
            acc += w;
        }
        if (cur.length > 0) cols.push(cur);
        return cols;
    }

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

    // Приёмник клавиш: слой держит клавиатуру, пока окно показано.
    Item {
        id: keys
        focus: true
        Keys.onPressed: (ev) => {
            if (ev.key === Qt.Key_Escape) {
                ev.accepted = true;
                KeysHelp.hide();
            }
        }
    }
    onVisibleChanged: if (visible) keys.forceActiveFocus()

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: body.implicitWidth + 2 * 24
        height: body.implicitHeight + 2 * 18
        color: Theme.tileBg
        border.color: Theme.tileBorder
        border.width: 1
        radius: Theme.tileRadius

        // Клики по карточке окно не закрывают.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Column {
            id: body
            x: 24
            y: 18
            spacing: 8

            Item {
                width: Math.max(cols.implicitWidth, 600)
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ГОРЯЧИЕ КЛАВИШИ"
                    color: Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Shift+Super+/ или Escape — закрыть"
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                }
            }

            Rectangle {
                width: Math.max(cols.implicitWidth, 600)
                height: 1
                color: Theme.yellow
            }

            // Ошибка загрузки: конфиг с ошибкой или бинарник демона без --json.
            Text {
                visible: KeysHelp.error !== ""
                width: Math.max(cols.implicitWidth, 600)
                text: "Перечень клавиш не получен:\n" + KeysHelp.error
                wrapMode: Text.Wrap
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }
            Text {
                visible: KeysHelp.loading && KeysHelp.groups.length === 0
                text: "Загрузка…"
                color: Theme.gray
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }

            Row {
                id: cols
                spacing: 36

                Repeater {
                    model: win.layout

                    Column {
                        id: column
                        required property var modelData
                        width: win.columnWidth
                        spacing: 0

                        Repeater {
                            model: column.modelData

                            Column {
                                id: group
                                required property var modelData
                                width: win.columnWidth

                                Item {
                                    width: parent.width
                                    height: win.headHeight
                                    Text {
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 6
                                        text: group.modelData.name.toUpperCase()
                                        color: Theme.gray
                                        font.family: Theme.fontFamily
                                        font.pointSize: Theme.pt(Theme.titleSize)
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
                                            id: label
                                            width: win.labelWidth
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.modelData.label
                                            elide: Text.ElideRight
                                            color: Theme.yellow
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                        }
                                        Text {
                                            x: win.labelWidth + 12
                                            width: parent.width - x
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.modelData.desc
                                            elide: Text.ElideRight
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 16
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
