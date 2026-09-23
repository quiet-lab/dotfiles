// Плитки рабочих столов (спецификация qs-workspaces): восемь плиток шириной
// 274 px, иконки окон слева, номер справа. Плитка неактивного стола — 274×36,
// плитка активного стола (того, на котором композитор) — двойной высоты 274×82:
// ровно две плитки и зазор, поэтому плитки ниже неё сдвигаются на целую плитку,
// а высота всего блока не меняется. Состояние — из модуля Hyprland (события
// сокета), окна на special:hidden показываются приглушёнными в плитке стола,
// с которого были скрыты (design D5).
// Плитка активного стола: верхний ряд — табы workspace демона workspaced
// (синглтон Wsd) в порядке списка стола; активный таб чёрный и сливается
// с нижним рядом, неактивные лежат на тёмно-серой полосе. Нижний ряд — окна
// активного workspace и свободные окна стола. Плитка неактивного стола — один
// ряд: иконки workspace (активный подсвечен, неактивные затенены), затем окна
// активного workspace и свободные окна. Окна неактивных workspace не
// показываются. Клик по табу или иконке workspace поднимает его на этом столе.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Shapes
import qs

Item {
    id: root
    width: 274
    // Семь одинарных плиток и одна двойная (шаг плиток 46 px, зазор 10 px).
    height: count * 46 - 10 + 46

    // Номер активного стола среди плиток (0…7) или -1, если композитор на столе
    // вне 1…8: тогда двойной плитки нет, и блок снизу остаётся пустым.
    readonly property int activeIndex: {
        const n = Number(focusedName);
        return Number.isInteger(n) && n >= 1 && n <= count ? n - 1 : -1;
    }
    // Лимит табов: при ширине полосы 230 px и наименьшей ширине таба 24 px
    // с зазором 2 px помещается восемь; при большем числе показываются семь
    // и метка «+N».
    readonly property int tabLimit: 8

    readonly property int count: 8
    readonly property string hiddenWs: "special:hidden"
    readonly property var shells: ["bash", "zsh", "fish", "sh", "dash", "nu"]
    // Класс окна wezterm: имя программы берётся из заголовка «<программа> · …».
    readonly property var terminalClasses: ["org.wezfurlong.wezterm", "wezterm"]

    // Стол происхождения скрытых окон: адрес → имя стола.
    property var origins: ({})
    // Окна по столам: имя стола → массив записей { address, appId, title, icon, name, hidden }.
    property var byWs: ({})
    property string focusedName: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.name : "1"

    // --- Иконки ---
    // Кандидаты источника иконки для AppIcon: путь из записи .desktop, иконка темы,
    // файлы в ~/.local/share/icons (иконки программ из mise, например yazi).
    function iconPath(name) {
        if (!name) return "";
        if (name.startsWith("/")) return "file://" + name;
        return Quickshell.hasThemeIcon(name) ? Quickshell.iconPath(name) : "";
    }
    function candidates(names) {
        const home = Quickshell.env("HOME");
        const out = [];
        for (const n of names) {
            if (!n) continue;
            const p = iconPath(n);
            if (p) out.push(p);
            if (!n.startsWith("/")) {
                out.push("file://" + home + "/.local/share/icons/" + n + "/" + n + ".png");
                out.push("file://" + home + "/.local/share/icons/" + n + ".png");
                out.push("file://" + home + "/.local/share/icons/" + n + ".svg");
            }
        }
        out.push(Quickshell.iconPath("application-x-executable"));
        return out;
    }
    function lastComponent(cls) {
        const i = cls.lastIndexOf(".");
        return i >= 0 ? cls.substring(i + 1) : cls;
    }
    // Возвращает { icon, name } для класса окна и его заголовка.
    function resolve(appId, title) {
        let cls = appId || "";
        if (terminalClasses.indexOf(cls) >= 0) {
            const sep = title.indexOf(" · ");
            const prog = sep > 0 ? title.substring(0, sep) : "";
            const t = DesktopEntries.heuristicLookup("wezterm");
            const term = [t ? t.icon : "", "utilities-terminal"];
            if (prog && shells.indexOf(prog) < 0) {
                const e = DesktopEntries.heuristicLookup(prog);
                return { icon: candidates([e ? e.icon : "", prog].concat(term)), name: e ? e.name : prog };
            }
            return { icon: candidates(term), name: t ? t.name : "WezTerm" };
        }
        const entry = DesktopEntries.heuristicLookup(cls);
        const icon = candidates([entry ? entry.icon : "", cls.toLowerCase(), lastComponent(cls).toLowerCase()]);
        return { icon: icon, name: entry ? entry.name : lastComponent(cls) };
    }

    // --- Модель ---
    function rebuild() {
        const map = {};
        const orig = origins;
        const list = Hyprland.toplevels.values;
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            if (!t.address) continue;
            const ws = t.workspace ? t.workspace.name : "";
            if (!ws) continue;
            let target = ws;
            let hidden = false;
            if (ws === hiddenWs) {
                hidden = true;
                if (!orig[t.address]) orig[t.address] = focusedName;
                target = orig[t.address];
            } else if (ws.startsWith("special:")) {
                continue;
            } else {
                orig[t.address] = ws;
            }
            const ipc = t.lastIpcObject || {};
            const appId = (t.wayland && t.wayland.appId) || ipc.class || "";
            const r = resolve(appId, t.title || "");
            if (!map[target]) map[target] = [];
            map[target].push({ address: t.address, appId: appId, title: t.title || "", icon: r.icon, name: r.name, hidden: hidden, ws: target, active: !!t.activated });
        }
        // Забыть адреса закрытых окон.
        const alive = {};
        for (let i = 0; i < list.length; i++) alive[list[i].address] = true;
        for (const a in orig) if (!alive[a]) delete orig[a];
        origins = orig;
        byWs = map;
    }

    // Список строится прямо в обработчике события: к моменту, когда обработчик
    // получает событие композитора, Hyprland.toplevels уже обновлён (проверено
    // 22.09.2026: на openwindow новое окно в списке есть, на closewindow его уже
    // нет). Одно действие пользователя даёт два-три события и столько же проходов
    // по списку окон — он короткий, и откладывать перестроение незачем.
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            switch (ev.name) {
            case "openwindow": case "closewindow": case "movewindowv2": case "windowtitlev2":
            case "activewindowv2": case "workspacev2": case "focusedmonv2":
                root.rebuild();
                break;
            }
        }
    }
    Connections {
        target: Hyprland.toplevels
        function onObjectInsertedPost() { root.rebuild(); }
        function onObjectRemovedPost() { root.rebuild(); }
    }
    // Записи .desktop загружаются после старта панели: иконки и названия
    // пересчитываются, когда список приложений пополняется.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.rebuild(); }
    }
    Component.onCompleted: { Hyprland.refreshToplevels(); rebuild(); }

    // --- Действия ---
    function dispatch(lua) { Hyprland.dispatch(lua); }
    // Несколько диспетчеров одним запросом и строго по порядку: отдельные запросы
    // Hyprland.dispatch уходят асинхронно и могут обогнать друг друга (фокус
    // приходил раньше переноса со special:hidden, и окно фокус не получало).
    // Обёртка hl.dispatch(<текст>) принимает выражение, поэтому цепочка — вызов
    // функции, которая выполняет первые шаги и возвращает последний диспетчер.
    function chain(list) {
        const head = list.slice(0, -1).map(d => "hl.dispatch(" + d + ")").join("; ");
        dispatch("(function() " + head + (head ? "; " : "") + "return " + list[list.length - 1] + " end)()");
    }
    // Модуль отдаёт адрес без префикса 0x, а селектор Hyprland требует address:0x….
    function sel(w) { return "'address:0x" + w.address + "'"; }
    function focusWs(n) { dispatch("hl.dsp.focus({ workspace = " + n + " })"); }
    function activate(w) {
        // Повторный клик по иконке окна в фокусе скрывает его (как сворачивание с панели задач).
        if (w.active && !w.hidden) { hide(w); return; }
        const steps = [];
        if (w.hidden) steps.push("hl.dsp.window.move({ workspace = " + w.ws + ", window = " + sel(w) + ", follow = false })");
        steps.push("hl.dsp.focus({ window = " + sel(w) + " })");
        // Фокус не поднимает плавающее окно над остальными: без подъёма под курсором
        // остаётся другое окно, и клик по нему отдаёт фокус ему.
        steps.push("hl.dsp.window.bring_to_top()");
        chain(steps);
    }
    function hide(w) { dispatch("hl.dsp.window.move({ workspace = '" + hiddenWs + "', window = " + sel(w) + ", follow = false })"); }
    function closeWin(w) { dispatch("hl.dsp.window.close({ window = " + sel(w) + " })"); }
    function moveTo(w, n) { dispatch("hl.dsp.window.move({ workspace = " + n + ", window = " + sel(w) + ", follow = false })"); }

    function menuFor(w) {
        const items = [{ label: "Показать", action: () => activate(w) }];
        if (!w.hidden) items.push({ label: "Скрыть", action: () => hide(w) });
        items.push({ label: "Закрыть", action: () => closeWin(w) });
        items.push({ separator: true });
        for (let n = 1; n <= count; n++) {
            if (String(n) === w.ws) continue;
            items.push({ label: "На стол " + n, action: () => moveTo(w, n) });
        }
        return items;
    }
    function infoFor(w) {
        const lines = [w.name, w.title, w.appId, "Стол " + w.ws];
        if (w.hidden) lines.push("Скрыто");
        return lines;
    }

    // --- Workspace демона ---
    // Список workspace стола в порядке списка демона, то есть в порядке
    // попадания на стол: демон добавляет workspace в конец и не переставляет
    // его при поднятии, поэтому позиции иконок при переключении не меняются.
    function wsListFor(wsName) {
        const d = Wsd.desktops[wsName];
        if (!d || !d.workspaces) return [];
        return d.workspaces.map(w => ({ kind: "ws", name: w.name, icon: candidates([w.icon || "folder"]), active: !!w.active, apps: w.apps || [], windows: w.windows || [], desktop: Number(wsName) }));
    }
    // Ряд иконок плитки: сначала все workspace стола по порядку списка (только
    // у плитки неактивного стола, withWs; у активного они стоят табами), затем
    // окна активного workspace (по списку адресов от демона), затем свободные
    // окна стола. Окна неактивных workspace демон паркует на special:pool, и в
    // список окон стола они не попадают; окно, которое по списку демона
    // принадлежит неактивному workspace, но осталось на столе, тоже не
    // показывается. Лимит 10 и «+N» считаются по сумме иконок ряда.
    function itemsFor(wins, wsList, withWs) {
        const norm = a => String(a || "").toLowerCase().replace(/^0x/, "");
        const items = withWs ? wsList.slice() : [];
        const used = {};
        // Адреса окон неактивных workspace: в ряд свободных окон они не идут.
        const parked = {};
        for (const ws of wsList) {
            if (ws.active) continue;
            ws.windows.forEach(a => { parked[norm(a)] = true; });
        }
        for (const ws of wsList) {
            if (!ws.active) continue;
            const own = {};
            ws.windows.forEach(a => { own[norm(a)] = true; });
            for (const w of wins) {
                const a = norm(w.address);
                if (own[a] && !used[a]) {
                    used[a] = true;
                    items.push(Object.assign({ kind: "win" }, w));
                }
            }
        }
        for (const w of wins) if (!used[norm(w.address)] && !parked[norm(w.address)]) items.push(Object.assign({ kind: "win" }, w));
        return items;
    }
    function wsMenuFor(w) {
        return [
            { label: "Поднять", action: () => Wsd.raise(w.name, w.desktop) },
            { label: "Убрать со стола", action: () => Wsd.remove(w.name, w.desktop) },
        ];
    }
    function wsInfoFor(w) {
        const lines = ["workspace " + w.name, (w.active ? "активен" : "неактивен") + " на столе " + w.desktop];
        for (const a of w.apps) lines.push("  " + a);
        return lines;
    }

    // --- Плитки ---
    Repeater {
        model: root.count
        Rectangle {
            id: row
            required property int index
            readonly property string wsName: String(index + 1)
            readonly property var wins: root.byWs[wsName] || []
            readonly property var wsList: root.wsListFor(wsName)
            readonly property bool active: root.activeIndex === index
            readonly property var items: root.itemsFor(wins, wsList, !active)

            // Табы активного стола: при переполнении — первые tabLimit − 1 и «+N».
            readonly property bool tabsOverflow: wsList.length > root.tabLimit
            readonly property var tabs: tabsOverflow ? wsList.slice(0, root.tabLimit - 1) : wsList
            // Ширина таба: 36 px, пока табы помещаются в полосу 230 px, иначе уже,
            // но не меньше 24 px (иконка 20 px и по 2 px с боков).
            readonly property int tabWidth: {
                const n = tabs.length;
                if (!n) return 36;
                const free = 230 - (tabsOverflow ? 26 : 0) - 2 * (n - 1);
                return Math.min(36, Math.max(24, Math.floor(free / n)));
            }
            readonly property int activeTab: tabs.findIndex(t => t.active)

            // Плитки ниже активной сдвинуты на целую плитку с зазором.
            y: index * 46 + (root.activeIndex >= 0 && index > root.activeIndex ? 46 : 0)
            width: 274
            height: active ? 82 : 36
            color: "transparent"
            border.color: Theme.tileBorder
            border.width: 1
            radius: Theme.tileRadius
            Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.focusWs(row.wsName)
            }

            // Содержимое с фоном плитки, левые углы под рамку. Обрезка нужна на
            // время анимации высоты: полоса табов не выходит за плитку.
            Rectangle {
                id: body
                x: 1; y: 1
                width: 272 - 30
                height: row.height - 2
                color: Theme.tileBg
                topLeftRadius: 11
                bottomLeftRadius: 11
                clip: true

                // ---- Полоса табов (только у активного стола) ----
                // Высота полосы 38 px: табы 32 px от y = 5 до линии основания
                // на y = 37. Серая заливка покрывает полосу везде, кроме
                // активного таба; жёлтая линия 1 px идёт по основанию и обводит
                // активный таб сверху и с боков, как вкладку браузера.
                Item {
                    id: strip
                    visible: row.active
                    width: body.width
                    height: 38

                    readonly property int tabTop: 5
                    readonly property int base: 37
                    readonly property int r: 6
                    readonly property bool hasActive: row.activeTab >= 0
                    readonly property real ax: 6 + row.activeTab * (row.tabWidth + 2)
                    readonly property real aw: row.tabWidth

                    // Полоса без активного таба: прямоугольник и линия основания.
                    Rectangle {
                        visible: !strip.hasActive
                        width: strip.width; height: strip.height
                        topLeftRadius: 11
                        color: Theme.tabBarBg
                    }
                    Rectangle {
                        visible: !strip.hasActive
                        y: strip.base
                        width: strip.width; height: 1
                        color: Theme.tileBorder
                    }

                    // Полоса с вырезом под активный таб.
                    Shape {
                        visible: strip.hasActive
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: -1
                            fillColor: Theme.tabBarBg
                            startX: 0; startY: 11
                            PathArc { x: 11; y: 0; radiusX: 11; radiusY: 11 }
                            PathLine { x: strip.width; y: 0 }
                            PathLine { x: strip.width; y: strip.height }
                            PathLine { x: strip.ax + strip.aw; y: strip.height }
                            PathLine { x: strip.ax + strip.aw; y: strip.tabTop + strip.r }
                            PathArc { x: strip.ax + strip.aw - strip.r; y: strip.tabTop; radiusX: strip.r; radiusY: strip.r; direction: PathArc.Counterclockwise }
                            PathLine { x: strip.ax + strip.r; y: strip.tabTop }
                            PathArc { x: strip.ax; y: strip.tabTop + strip.r; radiusX: strip.r; radiusY: strip.r; direction: PathArc.Counterclockwise }
                            PathLine { x: strip.ax; y: strip.height }
                            PathLine { x: 0; y: strip.height }
                        }
                        // Контур: основание слева, активный таб, основание справа.
                        // Координаты смещены на полпикселя, чтобы линия 1 px
                        // ложилась ровно на пиксели.
                        ShapePath {
                            strokeWidth: 1
                            strokeColor: Theme.tileBorder
                            fillColor: "transparent"
                            startX: 0; startY: strip.base + 0.5
                            PathLine { x: strip.ax + 0.5; y: strip.base + 0.5 }
                            PathLine { x: strip.ax + 0.5; y: strip.tabTop + strip.r + 0.5 }
                            PathArc { x: strip.ax + strip.r + 0.5; y: strip.tabTop + 0.5; radiusX: strip.r; radiusY: strip.r }
                            PathLine { x: strip.ax + strip.aw - strip.r - 0.5; y: strip.tabTop + 0.5 }
                            PathArc { x: strip.ax + strip.aw - 0.5; y: strip.tabTop + strip.r + 0.5; radiusX: strip.r; radiusY: strip.r }
                            PathLine { x: strip.ax + strip.aw - 0.5; y: strip.base + 0.5 }
                            PathLine { x: strip.width; y: strip.base + 0.5 }
                        }
                    }

                    Repeater {
                        model: row.tabs
                        Item {
                            id: tab
                            required property var modelData
                            required property int index
                            readonly property bool current: !!modelData.active
                            x: 6 + index * (row.tabWidth + 2)
                            y: strip.tabTop
                            width: row.tabWidth
                            height: strip.base - strip.tabTop

                            // Подсветка неактивного таба при наведении.
                            Rectangle {
                                visible: !tab.current && tabMouse.containsMouse
                                x: 1; y: 1
                                width: parent.width - 2; height: parent.height - 1
                                topLeftRadius: strip.r - 1
                                topRightRadius: strip.r - 1
                                color: Theme.background
                            }
                            // Разделитель между соседними неактивными табами.
                            Rectangle {
                                visible: !tab.current && tab.index < row.tabs.length - 1 && tab.index + 1 !== row.activeTab
                                x: parent.width
                                y: (parent.height - height) / 2
                                width: 2; height: 16
                                color: "transparent"
                                Rectangle { x: 0.5; width: 1; height: parent.height; color: Theme.gray }
                            }
                            AppIcon {
                                anchors.centerIn: parent
                                width: 20; height: 20
                                opacity: tab.current ? 1 : 0.7
                                sources: tab.modelData.icon
                            }
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onEntered: Popups.hoverInfo.show(tab, root.wsInfoFor(tab.modelData), "ws-" + row.wsName)
                                onExited: Popups.hoverInfo.hide(tab)
                                onClicked: (m) => {
                                    Popups.hoverInfo.hide(tab);
                                    if (m.button === Qt.RightButton) Popups.menu.open(tab, root.wsMenuFor(tab.modelData));
                                    else Wsd.raise(tab.modelData.name, tab.modelData.desktop);
                                }
                            }
                        }
                    }
                    Text {
                        visible: row.tabsOverflow
                        x: 6 + row.tabs.length * (row.tabWidth + 2)
                        y: strip.tabTop
                        height: strip.base - strip.tabTop
                        verticalAlignment: Text.AlignVCenter
                        text: "+" + (row.wsList.length - row.tabs.length)
                        color: Theme.yellow
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }

                // ---- Ряд иконок ----
                // У одинарной плитки ряд 24 px стоит с отступами 5 px сверху и
                // снизу; у двойной — по центру области под полосой табов.
                Row {
                    x: 9
                    y: row.active ? strip.height + Math.max(0, (body.height - strip.height - 24) / 2) : (body.height - 24) / 2
                    spacing: 0
                    Repeater {
                        model: row.items.slice(0, 10)
                        Rectangle {
                            id: btn
                            required property var modelData
                            readonly property bool isWs: modelData.kind === "ws"
                            width: 24; height: 24; radius: 6
                            // Активный workspace подсвечен, неактивный затенён; скрытое окно тоже затенено.
                            color: btnMouse.containsMouse ? Theme.background : (isWs && modelData.active ? Qt.rgba(224/255, 175/255, 104/255, 0.3) : "transparent")
                            opacity: (isWs ? !modelData.active : modelData.hidden) ? 0.4 : 1
                            AppIcon {
                                anchors.centerIn: parent
                                width: 20; height: 20
                                sources: btn.modelData.icon
                            }
                            MouseArea {
                                id: btnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onEntered: Popups.hoverInfo.show(btn, btn.isWs ? root.wsInfoFor(btn.modelData) : root.infoFor(btn.modelData), "ws-" + row.wsName)
                                onExited: Popups.hoverInfo.hide(btn)
                                onClicked: (m) => {
                                    Popups.hoverInfo.hide(btn);
                                    if (btn.isWs) {
                                        if (m.button === Qt.RightButton) Popups.menu.open(btn, root.wsMenuFor(btn.modelData));
                                        else Wsd.raise(btn.modelData.name, btn.modelData.desktop);
                                    } else if (m.button === Qt.RightButton) Popups.menu.open(btn, root.menuFor(btn.modelData));
                                    else root.activate(btn.modelData);
                                }
                            }
                        }
                    }
                    Text {
                        visible: row.items.length > 10
                        leftPadding: 4
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        text: "+" + (row.items.length - 10)
                        color: Theme.gray
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }
            }

            // Блок номера во всю высоту содержимого, правые углы под рамку.
            Rectangle {
                x: 1 + 272 - 30; y: 1
                width: 30; height: row.height - 2
                topRightRadius: 11
                bottomRightRadius: 11
                color: row.active ? Theme.yellow : (rowMouse.containsMouse ? Theme.background : Qt.rgba(6/255, 6/255, 6/255, 0.6))
                Text {
                    anchors.centerIn: parent
                    text: row.wsName
                    color: row.active ? "#000000" : Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.Black
                }
            }
        }
    }
}
