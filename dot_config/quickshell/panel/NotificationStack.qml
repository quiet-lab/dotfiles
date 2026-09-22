// Столбик всплывающих уведомлений (спецификация qs-notifications, требования
// «Окно всплывающих уведомлений» и «Появление и уход карточек»): окно
// layer-shell справа от колонки панели на уровне плитки лаунчера — левый край
// в 10 px от колонки, нижний край вровень с нижним краем экрана, а нижняя
// карточка стоит в 10 px от него. Пространство имён слоя — panel, как
// у колонки: правило panel-blur в hyprland.lua размывает фон и под карточками.
//
// Окно занимает экран по высоте целиком (от 10 px сверху до нижнего края)
// и размера не меняет: карточки ездят внутри него, каждая анимирует своё
// смещение от нижнего края. Так новая карточка выезжает снизу и поднимает
// лежащие выше, а карточки ниже закрываемой не двигаются вовсе.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs

PanelWindow {
    id: stack
    required property var modelData
    screen: modelData

    readonly property int cardWidth: 444
    // Длительность переездов столбика — чуть больше растворения карточки
    // (150 мс), чтобы движение читалось глазом, а не мелькало.
    readonly property int moveDuration: 200

    anchors.left: true
    anchors.bottom: true
    margins.left: Theme.margin
    margins.bottom: 0
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
    implicitWidth: stack.cardWidth
    implicitHeight: stack.screen ? stack.screen.height - Theme.margin : 2150

    // Ввод принимает только занятая карточками часть окна: всё остальное окно
    // прозрачно и не должно перехватывать клики по окнам под ним.
    mask: Region {
        x: 0
        y: Math.max(0, stack.height - stack.extent)
        width: stack.width
        height: Math.min(stack.extent, stack.height)
    }

    // Высота занятой части столбика снизу вверх; ездит с той же анимацией,
    // что и карточки, поэтому область ввода следует за ними.
    property real extent: 0
    Behavior on extent {
        NumberAnimation { duration: stack.moveDuration; easing.type: Easing.OutQuad }
    }

    // Расстановка: каждой карточке задаётся смещение её верхнего края
    // от нижнего края окна, а карточка сама едет к нему с анимацией.
    // Закрываемая карточка остаётся в модели до конца растворения и место
    // своё сохраняет, поэтому при закрытии никто не двигается; вышележащие
    // опускаются уже после того, как она исчезла.
    function relayout() {
        for (let i = 0; i < rep.count; ++i) {
            const card = rep.itemAt(i);
            // Карточка ещё не создана или её высота ещё не посчитана:
            // расстановка подождёт события о готовой высоте, иначе столбик
            // проехал бы два раза — к неверным местам и обратно.
            if (!card || card.implicitHeight <= 1) return;
        }

        let offset = Theme.margin;
        let total = Theme.margin;
        for (let i = rep.count - 1; i >= 0; --i) {
            const card = rep.itemAt(i);
            offset += card.implicitHeight;
            card.targetOffset = offset;
            total = offset;
            offset += Theme.gap;
        }
        stack.extent = total;
        stack.dropOverflow(total);
    }

    // Столбик дорос до верхнего края экрана: самое старое уведомление, которое
    // ещё не растворяется, закрывается по истечении, растворяется так же, как
    // по клику, и уходит в историю. За один раз выбирается одно: его место
    // освободится, когда растворение кончится, и расстановка повторится.
    function dropOverflow(total) {
        if (rep.count <= 1 || total <= stack.height) return;
        for (let i = 0; i < rep.count; ++i) {
            const card = rep.itemAt(i);
            if (!card || card.closing) continue;
            NotificationService.requestExpire(card.notification);
            return;
        }
    }

    Repeater {
        id: rep
        model: NotificationService.model
        onItemAdded: Qt.callLater(stack.relayout)
        onItemRemoved: Qt.callLater(stack.relayout)

        delegate: NotificationCard {
            required property var modelData
            notification: modelData
            width: stack.cardWidth
            moveDuration: stack.moveDuration
            x: 0
            // Пока расстановка не задала смещение, оно равно нулю: карточка
            // стоит верхним краем на нижней границе экрана, то есть целиком
            // за ней, и первой же расстановкой выезжает оттуда наверх.
            y: stack.height - offset
            onImplicitHeightChanged: Qt.callLater(stack.relayout)
        }
    }
}
