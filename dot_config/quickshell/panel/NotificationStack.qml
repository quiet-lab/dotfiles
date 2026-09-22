// Столбик всплывающих уведомлений (спецификация qs-notifications, требование
// «Окно всплывающих уведомлений»): окно layer-shell справа от колонки панели
// на уровне плитки лаунчера — левый край в 10 px от колонки, нижний в 10 px
// от низа экрана, по общему правилу геометрии сессии. Пространство имён слоя —
// panel, как у колонки: правило panel-blur в hyprland.lua размывает фон
// и под карточками.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs

PanelWindow {
    id: stack
    required property var modelData
    screen: modelData

    // Слой прижат к левому и нижнему краю рабочей области. Зону 330 px
    // резервирует колонка панели, поэтому левый край слоя отсчитывается
    // от неё, а не от края экрана.
    anchors.left: true
    anchors.bottom: true
    margins.left: Theme.margin
    margins.bottom: Theme.margin
    exclusiveZone: 0

    WlrLayershell.namespace: "panel"
    // Слой Overlay: уведомление видно и поверх полноэкранного окна.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Прозрачная поверхность: заливку несут карточки, промежутки между ними
    // остаются прозрачными и порогом ignore_alpha от размытия отсекаются.
    color: "transparent"
    surfaceFormat.opaque: false

    visible: NotificationService.shown.length > 0
    implicitWidth: 444
    implicitHeight: Math.max(1, column.implicitHeight)

    // Предельная высота столбика: от нижнего края до верхнего с тем же
    // отступом 10 px.
    readonly property int maxHeight: stack.screen ? stack.screen.height - 2 * Theme.margin : 2140

    // Столбик дорос до верхнего края: самое старое уведомление (верхнее)
    // закрывается по истечении и уходит в историю, освобождая место новому.
    // За один раз закрывается одно, и проверка тут же назначается снова:
    // высота столбика к моменту проверки может быть ещё не пересчитана, и
    // одного прохода на пачку уведомлений не хватает.
    function trim() {
        const list = NotificationService.shown;
        if (list.length <= 1) return;
        if (column.implicitHeight <= stack.maxHeight) return;
        list[0].expire();
        Qt.callLater(stack.trim);
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.gap

        // Qt.callLater: проверка выполняется после того, как разобрано текущее
        // событие и столбик пересчитан, а не в середине его перестроения.
        onImplicitHeightChanged: Qt.callLater(stack.trim)

        Repeater {
            model: NotificationService.model
            delegate: NotificationCard {
                required property var modelData
                notification: modelData
                width: column.width
            }
        }
    }
}
