// Окно подсказки клавиш (спецификация qs-keys-help): перечень цепочек сессии,
// сгруппированный по назначению, в карточке шириной 1920 px по центру рабочей
// области (экран без полосы панели) в оформлении плиток. Перечень — одна
// колонка с плавной прокруткой: колесо мыши, перетаскивание, стрелки,
// PageUp/PageDown, Home/End, Пробел/Shift+Пробел и клавиши в духе Vim (j/k,
// Ctrl+D/U, Ctrl+F/B, g g, G). Описание, которое не помещается в строку,
// переносится, и строка перечня растёт по содержимому. Окно layer-shell на слое
// Overlay занимает экран целиком: клик мимо карточки закрывает окно, а на время
// показа слой берёт клавиатуру монопольно, чтобы закрыть окно клавишей Escape
// и прокручивать перечень клавишами. Привязки композитора при этом работают,
// поэтому повторное Shift+Super+/ тоже закрывает окно. Сроков показа нет.
// Данные и состояние — в синглтоне KeysHelp.
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs
import qs.common

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
    // Шаг колеса мыши — три строки за щелчок.
    readonly property int wheelStep: 3 * rowHeight
    // Длительность плавной прокрутки, мс: движение с замедлением к концу
    // (Easing.OutCubic) за это время доходит до цели.
    readonly property int scrollDuration: 320
    // Первое g из пары g g уже нажато: следующее g ведёт в начало перечня.
    // Срока у пары нет (таймеры запрещены): пару сбрасывает любая другая клавиша.
    property bool gPending: false

    // Коды клавиш XKB (код evdev + 8), которые Qt под Wayland отдаёт
    // в nativeScanCode. Код не зависит от раскладки, поэтому клавиши в духе
    // Vim работают и при русской раскладке.
    readonly property var scan: ({ j: 44, k: 45, d: 40, u: 30, f: 41, b: 56, g: 42 })

    // Какая латинская буква нажата: при латинской раскладке — по самой
    // клавише, иначе (русская раскладка даёт кириллическую клавишу) — по коду
    // клавиши. Клавиша проверяется первой, потому что у виртуальной клавиатуры
    // (wtype) коды клавиш собственные и с кодами XKB не совпадают.
    function letter(ev) {
        if (ev.key >= Qt.Key_A && ev.key <= Qt.Key_Z)
            return String.fromCharCode(ev.key - Qt.Key_A + 97);
        for (const name in win.scan)
            if (ev.nativeScanCode === win.scan[name]) return name;
        return "";
    }

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

    // Плавный сдвиг прокрутки к y с ограничением пределами перечня. Новая
    // цель подхватывает движение с нынешнего положения, без остановки
    // и без скачка; цель, к которой анимация уже идёт, её не перезапускает,
    // иначе упор в начало или конец перечня растягивал бы подход к краю.
    function scrollTo(y) {
        const max = Math.max(0, flick.contentHeight - flick.height);
        const to = Math.max(0, Math.min(max, y));
        flick.cancelFlick();
        if (scrollAnim.running && to === scrollAnim.to) return;
        scrollAnim.stop();
        if (to === flick.contentY) return;
        scrollAnim.from = flick.contentY;
        scrollAnim.to = to;
        scrollAnim.start();
    }
    // Сдвиг на dy от цели идущей анимации, а если её нет — от нынешнего
    // положения: частые нажатия и щелчки колеса складываются, а не теряются.
    function scrollBy(dy) {
        win.scrollTo((scrollAnim.running ? scrollAnim.to : flick.contentY) + dy);
    }

    // Сведения для проверки (IPC keys state): карточка, прокрутка (цель идущей
    // анимации, если она идёт) и добавка
    // высоты перечня сверх строк высотой rowHeight — её дают перенесённые строки.
    Binding {
        target: KeysHelp
        property: "view"
        value: {
            let rows = 0;
            for (const g of KeysHelp.groups) rows += (g.keys || []).length;
            const extra = list.height - KeysHelp.groups.length * win.headHeight - rows * win.rowHeight;
            return "card=" + card.x + "," + card.y + " " + card.width + "x" + card.height
                + " scroll=" + Math.round(scrollAnim.running ? scrollAnim.to : flick.contentY) + "/" + Math.round(Math.max(0, flick.contentHeight - flick.height))
                + " wrapExtra=" + Math.round(extra);
        }
    }

    NumberAnimation {
        id: scrollAnim
        target: flick
        property: "contentY"
        duration: win.scrollDuration
        easing.type: Easing.OutCubic
    }

    // Приёмник клавиш: слой держит клавиатуру, пока окно показано.
    Item {
        id: keys
        focus: true
        Keys.onPressed: (ev) => {
            // Окно — высота области прокрутки без одной строки, чтобы строка
            // у края осталась видна; полокна — половина высоты области.
            const page = Math.max(win.rowHeight, flick.height - win.rowHeight);
            const half = Math.max(win.rowHeight, Math.round(flick.height / 2));
            const ctrl = (ev.modifiers & Qt.ControlModifier) !== 0;
            const shift = (ev.modifiers & Qt.ShiftModifier) !== 0;
            const plain = (ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0;
            // Одиночный Shift, Ctrl и прочие модификаторы пару g g не сбрасывают:
            // G набирается с Shift.
            if (ev.key === Qt.Key_Shift || ev.key === Qt.Key_Control
                    || ev.key === Qt.Key_Alt || ev.key === Qt.Key_Meta)
                return;
            const l = win.letter(ev);
            const pendingG = win.gPending;
            win.gPending = false;
            switch (ev.key) {
            case Qt.Key_Escape:
                KeysHelp.hide();
                break;
            case Qt.Key_Down:
                win.scrollBy(win.rowHeight);
                break;
            case Qt.Key_Up:
                win.scrollBy(-win.rowHeight);
                break;
            case Qt.Key_PageDown:
                win.scrollBy(page);
                break;
            case Qt.Key_PageUp:
                win.scrollBy(-page);
                break;
            case Qt.Key_Home:
                win.scrollTo(0);
                break;
            case Qt.Key_End:
                win.scrollTo(flick.contentHeight);
                break;
            case Qt.Key_Space:
                if (ctrl) return;
                win.scrollBy(shift ? -half : half);
                break;
            default:
                if (plain && !shift && l === "j") win.scrollBy(win.rowHeight);
                else if (plain && !shift && l === "k") win.scrollBy(-win.rowHeight);
                else if (ctrl && l === "d") win.scrollBy(half);
                else if (ctrl && l === "u") win.scrollBy(-half);
                else if (ctrl && l === "f") win.scrollBy(page);
                else if (ctrl && l === "b") win.scrollBy(-page);
                else if (plain && shift && l === "g") win.scrollTo(flick.contentHeight);
                else if (plain && !shift && l === "g") {
                    if (pendingG) win.scrollTo(0);
                    else win.gPending = true;
                } else return;
            }
            ev.accepted = true;
        }
    }
    // При каждом открытии перечень начинается сначала.
    onVisibleChanged: if (visible) {
        scrollAnim.stop();
        flick.cancelFlick();
        flick.contentY = 0;
        win.gPending = false;
        keys.forceActiveFocus();
    }

    Rectangle {
        id: card
        // По центру рабочей области: экран без полосы панели слева (та же
        // зона, которую панель объявляет композитору). При ширине экрана
        // 3840 это x = 330 + (3510 − 1920) / 2 = 1125, как у ячейки center
        // шаблонов демона.
        x: Theme.panelWidth + Math.round((parent.width - Theme.panelWidth - width) / 2)
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

        // Перечень одной колонкой с прокруткой. Перетаскивание и инерцию
        // обрабатывает сам Flickable, колесо — область wheel ниже (плавно,
        // по шагам), клавиши — приёмник keys выше.
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
            // Мягкая инерция перетаскивания: перечень после броска
            // тормозит постепенно, а скорость броска ограничена умеренной.
            flickDeceleration: 1500
            maximumFlickVelocity: 4000
            // Перетаскивание прерывает плавную прокрутку клавишами и колесом.
            onMovementStarted: scrollAnim.stop()

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

                            // Строка растёт по содержимому: подпись и описание
                            // переносятся каждое в своей колонке, первая строка
                            // обоих стоит там же, где стояла бы в строке высотой
                            // rowHeight.
                            Item {
                                id: row
                                required property var modelData
                                readonly property int pad: Math.max(0, Math.round((win.rowHeight - lineMetrics.height) / 2))
                                width: group.width
                                height: Math.max(win.rowHeight, Math.max(labelText.height, descText.height) + 2 * pad)

                                Text {
                                    id: labelText
                                    y: row.pad
                                    width: win.labelWidth
                                    text: row.modelData.label
                                    wrapMode: Text.Wrap
                                    color: Theme.yellow
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 32
                                }
                                Text {
                                    id: descText
                                    x: win.labelWidth + 24
                                    y: row.pad
                                    width: parent.width - x
                                    text: row.modelData.desc
                                    wrapMode: Text.Wrap
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

        // Колесо мыши и тачпад: щелчок колеса сдвигает цель прокрутки
        // на wheelStep, точная прокрутка тачпада (pixelDelta) — на свои
        // пиксели; в обоих случаях цель копится, а перечень едет к ней той же
        // анимацией, что и от клавиш. Кнопки мыши область не принимает —
        // их получает Flickable.
        MouseArea {
            id: wheel
            anchors.fill: flick
            acceptedButtons: Qt.NoButton
            onWheel: (w) => {
                if (w.pixelDelta.y !== 0)
                    win.scrollBy(-w.pixelDelta.y);
                else
                    win.scrollBy(-w.angleDelta.y / 120 * win.wheelStep);
                w.accepted = true;
            }
        }

        // Высота строки шрифта перечня: по ней строка перечня выравнивает
        // первую строку подписи и описания.
        FontMetrics {
            id: lineMetrics
            font.family: Theme.fontFamily
            font.pixelSize: 32
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
