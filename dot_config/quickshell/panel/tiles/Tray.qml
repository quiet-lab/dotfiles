// Трей (спецификация qs-tray-lang): значки StatusNotifierItem столбиком, новые
// сверху; левый клик — основное действие, правый — меню DBusMenu, колесо —
// прокрутка элемента. Внизу кнопка громкости устройства вывода PipeWire по
// умолчанию с выдвижной панелью-ползунком (design D7).
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import QtQuick
import qs

Tile {
    id: tile
    width: 36
    height: 312

    // --- Значки ---
    // Новые элементы добавляются в конец модели, а показываются сверху.
    readonly property var items: SystemTray.items.values.slice().reverse()

    // Координаты внутри Tile отсчитываются от внутреннего отступа 10 px; значки
    // стоят в 8 px от рамки (отступ 7 px плюс рамка 1 px, как в eww).
    Column {
        x: -2; y: 0
        spacing: 6
        Repeater {
            model: tile.items
            Item {
                id: entry
                required property var modelData
                width: 20; height: 20
                Image {
                    anchors.fill: parent
                    source: entry.modelData.icon
                    sourceSize: Qt.size(40, 40)
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onEntered: Popups.tooltip.show(entry, entry.modelData.tooltipTitle || entry.modelData.title || entry.modelData.id)
                    onExited: Popups.tooltip.hide(entry)
                    onClicked: (m) => {
                        Popups.tooltip.hide(entry);
                        if (m.button === Qt.RightButton) {
                            if (entry.modelData.hasMenu) trayMenu.open(entry, entry.modelData.menu);
                        } else if (m.button === Qt.MiddleButton) {
                            entry.modelData.secondaryActivate();
                        } else if (entry.modelData.onlyMenu && entry.modelData.hasMenu) {
                            trayMenu.open(entry, entry.modelData.menu);
                        } else {
                            entry.modelData.activate();
                        }
                    }
                    onWheel: (w) => entry.modelData.scroll(w.angleDelta.y > 0 ? 1 : -1, false)
                }
            }
        }
    }

    TrayMenuPopup { id: trayMenu }

    // --- Громкость ---
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property int percent: Math.round(volume * 100)

    function setVolume(v) {
        if (!sink || !sink.audio) return;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }
    function step(delta) { setVolume(Math.round(volume * 20 + delta) / 20); }
    function glyph() {
        if (muted || percent === 0) return "󰝟";
        if (percent < 34) return "󰕿";
        if (percent < 67) return "󰖀";
        return "󰕾";
    }

    // Панель громкости выезжает снизу вверх над кнопкой: от верха плитки до
    // верхнего края кнопки динамика (277 px от верха), внутри рамки; фон
    // непрозрачный, чтобы перекрывать значки трея, но не динамик.
    // Панель выдвигает наведение на кнопку динамика, а убирает уход указателя
    // со всей плитки. Область наведения — плитка целиком, а не сама панель:
    // она не движется, поэтому указатель, поднявшийся к ползунку раньше, чем
    // панель доехала доверху, наведения не теряет. Выдвинутая панель занимает
    // место значков трея, так что указатель над ними всё равно над панелью.
    property bool showPanel: false

    // Плитка целиком: и панель, и кнопка лежат внутри, поэтому наведение на них
    // считается наведением на эту область. Координаты внутри Tile отсчитываются
    // от внутреннего отступа, и начало области сдвинуто на него назад; координаты
    // внутри самой области — уже от края плитки.
    Item {
        id: volArea
        x: -Theme.tilePadding - 1
        y: -(Theme.tilePadding + 1)
        width: tile.width
        height: tile.height

        HoverHandler {
            onHoveredChanged: if (!hovered) tile.showPanel = false
        }

        Item {
            id: panelClip
            x: 1; y: 1
            width: 34; height: 276
            clip: true

            Rectangle {
                id: volPanel
                width: 34
                height: 276
                y: tile.showPanel ? 0 : height
                Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: "#000000"
                topLeftRadius: 11
                topRightRadius: 11
                bottomLeftRadius: 8
                bottomRightRadius: 8

                // Ползунок 0…100 %: полоса 12 px шириной, заполнение снизу вверх.
                Item {
                    id: slider
                    x: 11; y: 14
                    width: 12; height: 230
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Theme.background
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * tile.volume
                        radius: 6
                        color: Theme.yellow
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        function apply(y) { tile.setVolume(1 - (y - 6) / slider.height); }
                        onPressed: (m) => apply(m.y)
                        onPositionChanged: (m) => { if (pressed) apply(m.y); }
                        onWheel: (w) => tile.step(w.angleDelta.y > 0 ? 1 : -1)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: slider.y + slider.height + 8
                    text: tile.percent
                    color: Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                }
            }
        }

        // Кнопка громкости: глиф 23 px, поле снизу 5 px, по центру плитки.
        Item {
            id: volBtn
            x: 1; y: 312 - 1 - 5 - 28
            width: 34; height: 28
            Text {
                anchors.centerIn: parent
                text: tile.glyph()
                color: Theme.yellow
                font.family: Theme.fontFamily
                font.pixelSize: 23
            }
            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: tile.showPanel = true
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) { if (tile.sink && tile.sink.audio) tile.sink.audio.muted = !tile.muted; }
                    else Run.detached(["pavucontrol"]);
                }
                onWheel: (w) => tile.step(w.angleDelta.y > 0 ? 1 : -1)
            }
        }
    }
}
