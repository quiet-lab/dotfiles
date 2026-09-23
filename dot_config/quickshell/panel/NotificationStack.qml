// Столбик непросмотренных уведомлений (спецификация qs-notifications,
// требования «Окно всплывающих уведомлений» и «Движение столбика»): окно
// layer-shell справа от колонки панели на уровне плитки лаунчера — левый край
// в 10 px от колонки, нижний край нижней карточки в 10 px от низа экрана.
// Пространство имён слоя — panel, как у колонки: правило panel-blur
// в hyprland.lua размывает фон и под карточками.
//
// Окно занимает экран по высоте целиком (от 10 px сверху до нижнего края)
// и размера не меняет: карточки ездят внутри него, каждая анимирует своё
// смещение от нижнего края. Карточки столбик создаёт и уничтожает сам,
// по одной на запись: так закрытие одной не задевает анимации соседних.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs
import qs.common

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

    visible: NotificationService.onScreen.length > 0
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

    // Карточки по номеру записи.
    property var cards: ({})

    Item { id: field; anchors.fill: parent }

    Component { id: cardComponent; NotificationCard {} }

    // Состав столбика изменился: завести карточки новым записям и убрать
    // карточки тех, что ушли с экрана.
    function sync() {
        const list = NotificationService.onScreen;
        const live = {};
        for (const rec of list) {
            live[rec.key] = true;
            if (stack.cards[rec.key]) continue;
            const card = cardComponent.createObject(field, {
                record: rec,
                width: stack.cardWidth,
                moveDuration: stack.moveDuration,
                x: 0
            });
            if (!card) continue;
            stack.cards[rec.key] = card;
            card.implicitHeightChanged.connect(stack.schedule);
        }
        for (const key in stack.cards) {
            if (live[key]) continue;
            const card = stack.cards[key];
            delete stack.cards[key];
            card.vanish();
        }
        stack.relayout();
    }

    function schedule() { Qt.callLater(stack.relayout); }

    // Расстановка: каждой карточке задаётся смещение её верхнего края
    // от нижнего края окна, а карточка сама едет к нему с анимацией.
    // Растворяющаяся карточка остаётся на экране до конца анимации и место
    // своё сохраняет, поэтому при закрытии никто не двигается; вышележащие
    // опускаются уже после того, как она исчезла.
    function relayout() {
        const list = NotificationService.onScreen;
        for (const rec of list) {
            const card = stack.cards[rec.key];
            // Карточка ещё не создана или её высота ещё не посчитана:
            // расстановка подождёт события о готовой высоте, иначе столбик
            // проехал бы два раза — к неверным местам и обратно.
            if (!card || card.implicitHeight <= 1) return;
        }

        let offset = Theme.margin;
        let total = Theme.margin;
        for (let i = list.length - 1; i >= 0; --i) {
            const card = stack.cards[list[i].key];
            card.y = Qt.binding(() => stack.height - card.offset);
            offset += card.implicitHeight;
            card.targetOffset = offset;
            total = offset;
            offset += Theme.gap;
        }
        stack.extent = total;
        stack.dropOverflow(list, total);
    }

    // Столбик дошёл до верхнего края экрана: самое старое уведомление, которое
    // ещё не растворяется, помечается просмотренным — растворяется так же, как
    // по клику, уходит с экрана и остаётся в истории. За один раз выбирается
    // одно: его место освободится, когда растворение кончится, и новая
    // расстановка при необходимости выберет следующее.
    function dropOverflow(list, total) {
        if (list.length <= 1 || total <= stack.height) return;
        for (const rec of list) {
            const card = stack.cards[rec.key];
            if (!card || card.closing) continue;
            NotificationService.requestSeen(rec);
            return;
        }
    }

    Connections {
        target: NotificationService
        function onOnScreenChanged() { Qt.callLater(stack.sync); }
    }

    Component.onCompleted: stack.sync()
}
