// Лаунчер (спецификация qs-launcher, design D9): фильтр и сетка иконок приложений
// из DesktopEntries по 7 в ряд; без фильтра — ряд частых приложений и разделы,
// с фильтром — плоский список по частоте запусков. Статистика запусков хранится
// в ~/.local/share/quickshell-panel/usage.json.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs

Tile {
    id: tile
    height: 320

    readonly property string statsDir: Quickshell.env("HOME") + "/.local/share/quickshell-panel"
    readonly property string statsPath: statsDir + "/usage.json"
    readonly property int perRow: 7
    readonly property int cell: 38
    readonly property int iconSize: 32

    // Разделы в порядке приоритета: первая подходящая категория определяет раздел.
    readonly property var sections: [
        { title: "Стандартные", cats: ["Utility"] },
        { title: "Разработка",  cats: ["Development"] },
        { title: "Образование", cats: ["Education"] },
        { title: "Игры",        cats: ["Game"] },
        { title: "Графика",     cats: ["Graphics"] },
        { title: "Мультимедиа", cats: ["AudioVideo", "Audio", "Video"] },
        { title: "Интернет",    cats: ["Network"] },
        { title: "Офис",        cats: ["Office"] },
        { title: "Наука",       cats: ["Science"] },
        { title: "Настройки",   cats: ["Settings"] },
        { title: "Система",     cats: ["System"] }
    ]

    // --- Статистика запусков ---
    property var usage: ({})
    Process {
        id: mkdir
        command: ["mkdir", "-p", tile.statsDir]
        running: true
    }
    FileView {
        id: statsFile
        path: tile.statsPath
        printErrors: false
        onLoaded: {
            try { tile.usage = JSON.parse(statsFile.text()) || {}; } catch (e) { tile.usage = {}; }
            tile.rebuild();
        }
        onLoadFailed: { tile.usage = {}; tile.rebuild(); }
    }
    function bump(id) {
        const u = usage;
        u[id] = (u[id] || 0) + 1;
        usage = u;
        statsFile.setText(JSON.stringify(u, null, 2) + "\n");
        rebuild();
    }
    function count(id) { return usage[id] || 0; }

    // --- Модель сетки ---
    property string query: ""
    // Строки: { header: "Раздел" } или { apps: [entry, …] }.
    property var rows: []

    function sectionOf(entry) {
        const cats = entry.categories || [];
        for (const s of sections)
            for (const c of s.cats)
                if (cats.indexOf(c) >= 0) return s.title;
        return "Прочее";
    }
    function chunk(list) {
        const out = [];
        for (let i = 0; i < list.length; i += perRow) out.push({ apps: list.slice(i, i + perRow) });
        return out;
    }
    function byName(a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase(), "ru"); }

    function rebuild() {
        const all = DesktopEntries.applications.values.slice();
        const q = query.trim().toLowerCase();
        let out = [];
        if (q !== "") {
            const hits = all.filter(e => e.name.toLowerCase().indexOf(q) >= 0);
            hits.sort((a, b) => (count(b.id) - count(a.id)) || byName(a, b));
            out = chunk(hits);
        } else {
            const frequent = all.filter(e => count(e.id) > 0);
            frequent.sort((a, b) => (count(b.id) - count(a.id)) || byName(a, b));
            if (frequent.length > 0) out.push({ apps: frequent.slice(0, perRow) });
            const groups = {};
            for (const e of all) {
                const s = sectionOf(e);
                if (!groups[s]) groups[s] = [];
                groups[s].push(e);
            }
            const order = sections.map(s => s.title).concat(["Прочее"]);
            for (const title of order) {
                const list = groups[title];
                if (!list || list.length === 0) continue;
                list.sort(byName);
                out.push({ header: title });
                out = out.concat(chunk(list));
            }
        }
        rows = out;
    }
    // Список строится прямо в обработчике события: смена строки поиска, загрузка
    // счётчика запусков и пополнение списка записей .desktop приходят по одному,
    // пачки из них не складывается.
    onQueryChanged: rebuild()
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { tile.rebuild(); }
    }
    Component.onCompleted: rebuild()

    // --- Запуск ---
    function launch(entry) {
        if (entry.runInTerminal) {
            Run.detached(["wezterm", "--config-file", Quickshell.env("HOME") + "/.config/wezterm/apps.lua",
                "start", "--class", entry.id, "--"].concat(entry.command), entry.workingDirectory);
        } else {
            Run.detached(entry.command, entry.workingDirectory);
        }
        bump(entry.id);
        clearAndRelease();
    }
    function clearAndRelease() {
        search.text = "";
        release();
    }
    // Отдать клавиатуру окнам, не трогая текст фильтра.
    function release() {
        search.focus = false;
        if (Popups.panel) Popups.panel.releaseKeyboard();
    }
    // Композитор не всегда забирает клавиатуру у слоя по клику в окно, поэтому панель
    // отпускает её сама: при смене активного окна (клик по окну, Alt+Tab) и когда
    // указатель уходит с плитки при поле в фокусе.
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "activewindowv2" && search.activeFocus) tile.release();
        }
    }
    HoverHandler {
        onHoveredChanged: if (!hovered && search.activeFocus) tile.release()
    }
    function iconSources(entry) {
        const home = Quickshell.env("HOME");
        const out = [];
        for (const n of [entry.icon, entry.id]) {
            if (!n) continue;
            if (n.startsWith("/")) { out.push("file://" + n); continue; }
            if (Quickshell.hasThemeIcon(n)) out.push(Quickshell.iconPath(n));
            out.push("file://" + home + "/.local/share/icons/" + n + "/" + n + ".png");
            out.push("file://" + home + "/.local/share/icons/" + n + ".png");
        }
        out.push(Quickshell.iconPath("application-x-executable"));
        return out;
    }

    // --- Шапка: «APP:» и поле фильтра ---
    Item {
        id: header
        width: parent.width
        height: 22
        Text {
            id: appsTitle
            anchors.verticalCenter: parent.verticalCenter
            text: "APP:"
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.weight: Font.Black
        }
        Rectangle {
            anchors.left: appsTitle.right
            anchors.leftMargin: 5
            anchors.right: parent.right
            height: 22
            radius: 6
            color: Theme.yellow
            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                color: "#000000"
                selectionColor: "#000000"
                selectedTextColor: Theme.yellow
                font.family: Theme.fontFamily
                font.pointSize: Theme.pt(13.3)
                clip: true
                onTextChanged: tile.query = text
                Keys.onEscapePressed: tile.clearAndRelease()
                // Клавиатура ушла к окну (клик по нему): слой больше не просит фокус,
                // иначе следующий клик по любой плитке снова забрал бы ввод у окна.
                onActiveFocusChanged: if (!activeFocus && Popups.panel) Popups.panel.releaseKeyboard()
                Keys.onReturnPressed: {
                    // Enter запускает первое приложение отфильтрованного списка.
                    if (tile.query !== "" && tile.rows.length > 0 && tile.rows[0].apps && tile.rows[0].apps.length > 0)
                        tile.launch(tile.rows[0].apps[0]);
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
                // Режим OnDemand включается заранее, при наведении: композитор отдаёт
                // клавиатуру слою только по клику, а к моменту клика запрос уже стоит.
                onEntered: { Popups.tooltip.show(header, "Фильтр по названию"); if (Popups.panel) Popups.panel.grabKeyboard(); }
                onExited: { Popups.tooltip.hide(header); if (!search.activeFocus && Popups.panel) Popups.panel.releaseKeyboard(); }
                onClicked: { Popups.tooltip.hide(header); search.forceActiveFocus(); }
            }
        }
    }

    // --- Сетка с прокруткой ---
    ListView {
        id: grid
        anchors.top: header.bottom
        anchors.topMargin: 5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: tile.rows
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: rowItem
            required property var modelData
            readonly property bool isHeader: modelData.header !== undefined
            width: grid.width
            height: isHeader ? 26 : tile.cell

            Text {
                visible: rowItem.isHeader
                x: 2; y: 4
                text: rowItem.modelData.header || ""
                color: Theme.yellow
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: true
            }
            Row {
                visible: !rowItem.isHeader
                Repeater {
                    model: rowItem.isHeader ? [] : rowItem.modelData.apps
                    Rectangle {
                        id: appBtn
                        required property var modelData
                        width: tile.cell; height: tile.cell
                        radius: 8
                        color: appMouse.containsMouse ? Theme.background : "transparent"
                        AppIcon {
                            anchors.centerIn: parent
                            width: tile.iconSize; height: tile.iconSize
                            sources: tile.iconSources(appBtn.modelData)
                        }
                        MouseArea {
                            id: appMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: Popups.tooltip.show(appBtn, appBtn.modelData.name)
                            onExited: Popups.tooltip.hide(appBtn)
                            onClicked: { Popups.tooltip.hide(appBtn); tile.launch(appBtn.modelData); }
                        }
                    }
                }
            }
        }
    }
}
