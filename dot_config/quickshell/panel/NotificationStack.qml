// Столбик непросмотренных уведомлений (спецификация qs-notifications,
// требования «Окно всплывающих уведомлений» и «Движение столбика»): окно
// layer-shell поверх колонки панели — левый край карточек на x = 10 px, как
// у плиток, верхний край первой карточки в 10 px от верха экрана. Ширина
// карточки равна ширине плитки. Слой Overlay лежит выше колонки, поэтому
// карточки перекрывают её плитки. Пространство имён слоя — panel, как
// у колонки: правило panel-blur в hyprland.lua размывает фон и под карточками.
//
// Окно занимает экран по высоте целиком (от 10 px сверху до нижнего края)
// и размера не меняет: карточки ездят внутри него, каждая анимирует своё
// смещение от верхнего края. Самое старое уведомление стоит сверху, новое
// добавляется вниз и выезжает из-за нижнего края экрана, прежние стоят
// на месте. Карточки столбик создаёт и уничтожает сам, по одной на запись:
// так закрытие одной не задевает анимации соседних.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs
import qs.common

PanelWindow {
    id: stack
    required property var modelData
    screen: modelData

    readonly property int cardWidth: Theme.tileWidth
    // Длительность переездов столбика — чуть больше растворения карточки
    // (150 мс), чтобы движение читалось глазом, а не мелькало.
    readonly property int moveDuration: 200

    anchors.left: true
    anchors.top: true
    margins.left: Theme.margin
    margins.top: Theme.margin
    // Зону окно не резервирует и чужие зоны не учитывает (layer-shell
    // получает exclusive zone −1): иначе композитор отодвинул бы его вправо
    // за 330 px колонки, а столбик стоит поверх неё. Свойство exclusiveZone
    // не задаётся: его установка возвращает режим Normal.
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "panel"
    // Слой Overlay: уведомление видно поверх плиток колонки и поверх
    // полноэкранного окна.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Прозрачная поверхность: заливку несут карточки, промежутки между ними
    // остаются прозрачными и порогом ignore_alpha от размытия отсекаются.
    color: "transparent"
    surfaceFormat.opaque: false

    visible: NotificationService.onScreen.length > 0
    implicitWidth: stack.cardWidth
    implicitHeight: stack.screen ? stack.screen.height - Theme.margin : 2150

    // Ввод принимает только занятая карточками верхняя часть окна: всё, что
    // ниже столбика, прозрачно, и клики уходят плиткам колонки под ним.
    mask: Region {
        x: 0
        y: 0
        width: stack.width
        height: Math.min(stack.extent, stack.height)
    }

    // Высота занятой части столбика сверху вниз; ездит с той же анимацией,
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
            // Новая карточка начинает путь за нижним краем окна, то есть
            // за нижним краем экрана, и выезжает оттуда на своё место.
            const card = cardComponent.createObject(field, {
                record: rec,
                width: stack.cardWidth,
                moveDuration: stack.moveDuration,
                offset: stack.height,
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
    // от верхнего края окна, а карточка сама едет к нему с анимацией.
    // Растворяющаяся карточка остаётся на экране до конца анимации и место
    // своё сохраняет, поэтому при закрытии никто не двигается; нижележащие
    // поднимаются уже после того, как она исчезла, а вышележащие стоят.
    function relayout() {
        const list = NotificationService.onScreen;
        for (const rec of list) {
            const card = stack.cards[rec.key];
            // Карточка ещё не создана или её высота ещё не посчитана:
            // расстановка подождёт события о готовой высоте, иначе столбик
            // проехал бы два раза — к неверным местам и обратно.
            if (!card || card.implicitHeight <= 1) return;
        }

        let offset = 0;
        let total = 0;
        for (const rec of list) {
            const card = stack.cards[rec.key];
            card.offset = offset;
            total = offset + card.implicitHeight;
            offset = total + Theme.gap;
        }
        stack.extent = total;
        stack.dropOverflow(list, total);
    }

    // Нижняя карточка не умещается выше отступа 10 px от низа экрана:
    // самое старое (верхнее) уведомление, которое ещё не растворяется,
    // помечается просмотренным — растворяется так же, как по клику, уходит
    // с экрана и остаётся в истории. За один раз выбирается одно: его место
    // освободится, когда растворение кончится, остальные поднимутся,
    // и новая расстановка при необходимости выберет следующее. Пока какая-то
    // карточка растворяется, новое не выбирается: её место ещё занято,
    // и расстановка, вызванная приходом очередного уведомления, иначе
    // сбросила бы лишние карточки.
    function dropOverflow(list, total) {
        if (list.length <= 1 || total <= stack.height - Theme.margin) return;
        for (const rec of list) {
            const card = stack.cards[rec.key];
            if (card && card.closing) return;
        }
        NotificationService.requestSeen(list[0]);
    }

    Connections {
        target: NotificationService
        function onOnScreenChanged() { Qt.callLater(stack.sync); }
    }

    Component.onCompleted: stack.sync()
}
