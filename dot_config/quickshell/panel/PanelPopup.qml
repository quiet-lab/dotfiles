// Базовое всплывающее окно панели (спецификация qs-shell, требование «Всплывающие
// окна панели»): появляется справа от колонки с зазором gap на уровне элемента
// target, не резервирует зону и не следует за указателем. Оформление как у плиток,
// скругление popupRadius.
import Quickshell
import QtQuick

PopupWindow {
    id: popup

    // Элемент панели, на уровне которого показывается окно.
    property Item target: null
    // Сдвиг по вертикали относительно верха target (например, к строке под указателем).
    property real yOffset: 0
    // Точка привязки по x в координатах окна target: по умолчанию правее колонки с зазором.
    property real anchorX: Theme.panelWidth + Theme.gap
    default property alias content: inner.data
    property int padX: 12
    property int padY: 8
    // Указатель над окном: область сплошная и включает поля вокруг содержимого,
    // поэтому проход указателя у самой рамки наведение не теряет.
    readonly property alias hovered: frameHover.hovered

    anchor.window: target ? target.QsWindow.window : null
    anchor.rect: {
        if (!target) return Qt.rect(0, 0, 0, 0);
        const p = target.mapToItem(null, 0, 0);
        return Qt.rect(anchorX, p.y + yOffset, 0, target.height);
    }
    anchor.edges: Edges.Left | Edges.Top
    anchor.gravity: Edges.Right | Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideY

    color: "transparent"
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    Rectangle {
        id: frame
        implicitWidth: inner.childrenRect.width + 2 * popup.padX
        implicitHeight: inner.childrenRect.height + 2 * popup.padY
        color: Theme.tileBg
        border.color: Theme.tileBorder
        border.width: 1
        radius: Theme.popupRadius

        HoverHandler { id: frameHover }

        Item {
            id: inner
            x: popup.padX
            y: popup.padY
        }
    }
}
