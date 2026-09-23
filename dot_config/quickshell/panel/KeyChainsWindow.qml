// Карточка индикатора цепочки с выходом (спецификация qs-key-chains): путь
// подписей состояний («Приложения ▸ Поднять»), клавиши текущего состояния
// с описаниями и пометкой клавиш выхода и нижняя строка о Backspace и Escape.
// Окно layer-shell размером с карточку на слое Overlay вверху по центру
// рабочей области (экран без полосы панели), на 10 px ниже края экрана.
// Клавиатуру окно не берёт, а пустая маска ввода пропускает клики к окнам
// под карточкой: нажатия обрабатывает композитор. Окно существует, только
// пока режим открыт. Данные и состояние — в синглтоне KeyChains.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs
import qs.common

PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    readonly property int padX: 24
    readonly property int padY: 16
    readonly property int fontPx: 28
    readonly property int keyGap: 24

    anchors.right: true
    anchors.bottom: true
    // Карточка стоит в правом нижнем углу экрана с отступом Theme.margin
    // от обоих краёв (решение пользователя 23.09.2026: сначала вверху
    // по центру, затем по центру экрана, в итоге — правый нижний угол).
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    margins.right: Theme.margin
    margins.bottom: Theme.margin

    // Пространство имён панели: правило слоя размывает фон под карточкой,
    // как под плитками.
    WlrLayershell.namespace: "panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    color: "transparent"
    surfaceFormat.opaque: false
    visible: KeyChains.shown
    implicitWidth: card.width
    implicitHeight: card.height

    // Пустая область ввода: клики проходят к окнам под карточкой.
    mask: Region {}

    // Сведения для проверки (IPC chains state): положение и размер карточки
    // на экране.
    Binding {
        target: KeyChains
        property: "view"
        value: "card=right-bottom margins=" + win.margins.right + "," + win.margins.bottom + " " + card.width + "x" + card.height
    }

    // Ширина колонки клавиш: шрифт моноширинный, поэтому её задаёт самая
    // длинная подпись.
    TextMetrics {
        id: keyMetrics
        font.family: Theme.fontFamily
        font.pixelSize: win.fontPx
        text: {
            let longest = "";
            for (const k of KeyChains.keys)
                if ((k.label || k.key).length > longest.length) longest = k.label || k.key;
            return longest;
        }
    }

    Rectangle {
        id: card
        width: body.implicitWidth + 2 * win.padX
        height: body.implicitHeight + 2 * win.padY
        color: Theme.tileBg
        border.color: Theme.tileBorder
        border.width: 1
        radius: Theme.tileRadius

        // Черта под путём во всю ширину содержимого.
        Rectangle {
            x: win.padX
            y: body.y + pathText.height + body.spacing
            width: card.width - 2 * win.padX
            height: 1
            color: Theme.yellow
        }

        Column {
            id: body
            x: win.padX
            y: win.padY
            spacing: 6

            // Путь подписей от корня.
            Text {
                id: pathText
                text: KeyChains.path.join(" ▸ ")
                color: Theme.yellow
                font.family: Theme.fontFamily
                font.pixelSize: win.fontPx
                font.bold: true
            }

            // Место под черту: сама черта лежит вне колонки, иначе её ширина
            // зависела бы от ширины колонки, а та — от неё.
            Item {
                width: 1
                height: 1
            }

            Text {
                visible: KeyChains.loading && KeyChains.keys.length === 0
                text: "Загрузка…"
                color: Theme.gray
                font.family: Theme.fontFamily
                font.pixelSize: win.fontPx
            }
            Text {
                visible: KeyChains.error !== ""
                width: Math.min(implicitWidth, 1600)
                text: "Перечень клавиш не получен: " + KeyChains.error
                wrapMode: Text.Wrap
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: win.fontPx
            }

            // Клавиши текущего состояния: «клавиша — описание», у клавиши
            // выхода пометка «выход».
            Repeater {
                model: KeyChains.keys

                Row {
                    id: row
                    required property var modelData
                    spacing: win.keyGap

                    Text {
                        width: keyMetrics.width
                        text: row.modelData.label || row.modelData.key
                        color: Theme.yellow
                        font.family: Theme.fontFamily
                        font.pixelSize: win.fontPx
                        font.bold: true
                    }
                    Text {
                        text: row.modelData.desc
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: win.fontPx
                    }
                    Text {
                        visible: row.modelData.exit === true
                        text: "выход"
                        color: Theme.red
                        font.family: Theme.fontFamily
                        font.pixelSize: win.fontPx
                    }
                }
            }

            Text {
                text: (KeyChains.atRoot ? "Backspace — выход" : "Backspace — назад") + " · Escape — выход"
                color: Theme.gray
                font.family: Theme.fontFamily
                font.pixelSize: win.fontPx
            }
        }
    }
}
