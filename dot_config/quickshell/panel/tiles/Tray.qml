// Трей (спецификация qs-tray-lang): сверху значки туннелей amn0 и axata
// (состояние — синглтон Tunnels; левый клик — окно состояния и настроек,
// правый — меню действий), под ними значки StatusNotifierItem столбиком, новые
// сверху; левый клик — основное действие, правый — меню DBusMenu, колесо —
// прокрутка элемента. Внизу кнопка громкости устройства вывода PipeWire по
// умолчанию с выдвижной панелью-ползунком (design D7).
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import QtQuick
import qs
import qs.common

Tile {
    id: tile
    width: 36
    // Высота полосы трея: блок столов (358 px) без плитки уведомлений сверху
    // и без переключателя раскладки снизу, с зазорами 10 px (спецификация
    // qs-tray-lang). Над кнопкой громкости помещается восемь значков
    // (шаг 26 px от y = 8 px до кнопки на y = 232 px): два значка туннелей
    // и шесть StatusNotifierItem.
    height: 266

    // --- Значки ---
    // Новые элементы добавляются в конец модели, а показываются сверху.
    readonly property var items: SystemTray.items.values.slice().reverse()

    // Координаты внутри Tile отсчитываются от внутреннего отступа 10 px; значки
    // стоят в 8 px от рамки (отступ 7 px плюс рамка 1 px, как в eww).
    Column {
        x: -2; y: 0
        spacing: 6
        // Значки туннелей стоят первыми и на постоянных местах: amn0, затем axata.
        TunnelIcon { id: amnIcon; tunnel: "amn0" }
        TunnelIcon { id: axataIcon; tunnel: "axata" }
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

    // --- Значки туннелей ---
    // Глиф по туннелю, цвет по состоянию: поднят — зелёный, поднимается —
    // жёлтый, не поднят — серый, ошибка службы или действия — красный.
    readonly property var tunnelNames: ({ amn0: "Amnezia amn0", axata: "OpenVPN axata" })
    readonly property var stateNames: ({ up: "поднят", starting: "поднимается", down: "не поднят", failed: "ошибка" })
    function tunnelState(name) { return name === "amn0" ? Tunnels.amn : Tunnels.axata; }
    function tunnelColor(s) {
        if (s.error !== "" || s.state === "failed") return Theme.red;
        if (s.state === "up") return Theme.green;
        if (s.state === "starting") return Theme.yellow;
        return Theme.gray;
    }
    function tunnelTip(name) {
        const s = tunnelState(name);
        let t = tunnelNames[name] + ": " + stateNames[s.state];
        if (s.ip !== "") t += ", " + s.ip;
        if (name === "amn0" ? Tunnels.amnBusy : Tunnels.axataBusy) t += "\nвыполняется действие";
        if (s.error !== "") t += "\nошибка: " + s.error;
        return t;
    }
    // Действия туннеля: одни и те же для меню правого клика и кнопок окна.
    function tunnelActions(name) {
        const s = tunnelState(name);
        const up = s.state === "up" || s.state === "starting";
        // Служба amn0 активна, а устройства нет (ошибка): start ничего не сделает,
        // поэтому меню предлагает перезапуск и остановку, как у поднятого.
        const amnRunning = up || s.service === "active" || s.service === "activating";
        const items = [];
        if (name === "amn0") {
            const ctl = (verb) => ["sudo", "-n", "/usr/bin/systemctl", verb, "awg-quick@amn0"];
            if (amnRunning) {
                items.push({ label: "Перезапустить", action: () => Tunnels.act("amn0", ctl("restart")) });
                items.push({ label: "Остановить", action: () => Tunnels.act("amn0", ctl("stop")) });
            } else {
                items.push({ label: "Запустить", action: () => Tunnels.act("amn0", ctl("start")) });
            }
            items.push({ label: "Обновить списки стран", action: () => Tunnels.act("amn0", ["sudo", "-n", "/usr/local/sbin/amn-zones-update", "--force"]) });
        } else {
            if (up) items.push({ label: "Отключить", action: () => Tunnels.act("axata", ["nmcli", "con", "down", "id", "axata"]) });
            else items.push({ label: "Подключить", action: () => Tunnels.act("axata", ["nmcli", "--wait", "60", "con", "up", "id", "axata"]) });
            items.push({ label: "Настройки", action: () => Run.detached(s.uuid ? ["nm-connection-editor", "--edit=" + s.uuid] : ["nm-connection-editor"]) });
        }
        return items;
    }

    // Проверка без мыши: `qs -c panel ipc call tunnels state` — состояние обоих
    // туннелей; info — окно сведений, как левый клик (без захвата ввода), run —
    // действие меню по подписи пункта, shown — содержимое открытого окна, close.
    // Меню по IPC не открывается: оно захватывает ввод, а Wayland разрешает
    // захват только сразу после клика по панели. Панель одна (только монитор DP-2), имя цели не повторяется.
    IpcHandler {
        target: "tunnels"
        function state(): string { return JSON.stringify({ amn0: Tunnels.amn, axata: Tunnels.axata }); }
        function info(name: string): void { tile.openInfo(name === "amn0" ? amnIcon : axataIcon, false); }
        function close(): void { tunnelPopup.close(); Popups.menu.close(); }
        // Выполнить действие туннеля по подписи пункта меню, как выбор пункта.
        function run(name: string, label: string): string {
            const a = tile.tunnelActions(name).find(x => x.label === label);
            if (!a) return "нет действия " + label;
            return a.action() === false ? "занято: предыдущее действие ещё выполняется" : "ok";
        }
        // Текст окна или меню, открытого сейчас: заголовок и строки.
        function shown(): string {
            if (tunnelPopup.visible) return JSON.stringify({ title: tunnelPopup.title, rows: tunnelPopup.rows, log: tunnelPopup.log, actions: tunnelPopup.actions.map(a => a.label) });
            if (Popups.menu.visible) return JSON.stringify({ menu: Popups.menu.items.map(a => a.label) });
            return "";
        }
    }
    function openInfo(icon, grab) {
        // Сведения читаются один раз при открытии окна: клик — событие. Клик
        // по другому значку во время чтения запоминается, и по окончании
        // чтения сведения читаются заново уже для него.
        infoProc.target = icon;
        infoProc.grab = grab !== false;
        if (infoProc.running) return;
        infoProc.command = [Quickshell.shellDir + "/scripts/tunnelinfo", icon.tunnel];
        infoProc.running = true;
    }
    // Значок, нажатие на который закрыло его же окно (окно с захватом ввода
    // закрывается кликом вне себя ещё до onClicked значка). Отметка ставится
    // по состоянию «кнопка мыши нажата на этом значке» и снимается в onClicked.
    property Item closedByPress: null
    Connections {
        target: tunnelPopup
        function onVisibleChanged() {
            const t = tunnelPopup.target;
            if (!tunnelPopup.visible && t && t.pressed) tile.closedByPress = t;
        }
    }

    component TunnelIcon: Item {
        id: icon
        required property string tunnel
        readonly property var st: tile.tunnelState(tunnel)
        width: 20; height: 20
        Text {
            anchors.centerIn: parent
            text: icon.tunnel === "amn0" ? "󰖟" : "󰦝"
            color: tile.tunnelColor(icon.st)
            font.family: Theme.fontFamily
            font.pixelSize: 20
        }
        readonly property alias pressed: iconMouse.pressed
        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: tile.closedByPress = null
            onEntered: Popups.tooltip.show(icon, tile.tunnelTip(icon.tunnel))
            onExited: Popups.tooltip.hide(icon)
            onClicked: (m) => {
                Popups.tooltip.hide(icon);
                if (m.button === Qt.RightButton) {
                    Popups.menu.open(icon, tile.tunnelActions(icon.tunnel));
                } else if (tile.closedByPress === icon) {
                    // Окно этого значка закрыто нажатием на сам значок (клик вне
                    // окна с захватом ввода): повторный клик окно закрывает.
                    tile.closedByPress = null;
                } else if (tunnelPopup.visible && tunnelPopup.target === icon) {
                    tunnelPopup.close();
                } else {
                    tile.openInfo(icon);
                }
            }
        }
    }
    Process {
        id: infoProc
        property Item target: null
        property bool grab: true
        // Клик по соседнему значку во время чтения: по завершении процесса
        // сведения читаются заново уже для него.
        onRunningChanged: {
            const t = infoProc.target;
            if (!running && t && t.tunnel !== infoProc.command[1]) tile.openInfo(t, infoProc.grab);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const t = infoProc.target;
                // Сведения не того туннеля (ответ на прежний клик) не показываются.
                if (!t || t.tunnel !== infoProc.command[1]) return;
                let info = null;
                try { info = JSON.parse(text); } catch (e) { console.warn("tunnelinfo: не JSON:", text); return; }
                if (info.tunnel !== t.tunnel) return;
                tunnelPopup.open(t, tile.tunnelTip(t.tunnel), info, tile.tunnelActions(t.tunnel), infoProc.grab);
            }
        }
    }
    TunnelPopup { id: tunnelPopup }

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
            // Панель громкости закрывает плитку до верхнего края кнопки: её
            // высота считается от высоты плитки, а не задана числом.
            width: 34; height: tile.height - 36
            clip: true

            Rectangle {
                id: volPanel
                width: 34
                height: panelClip.height
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
                    width: 12; height: panelClip.height - 46
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
            x: 1; y: tile.height - 1 - 5 - 28
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
