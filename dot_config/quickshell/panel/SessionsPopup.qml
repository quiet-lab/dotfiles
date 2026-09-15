// Окно выбора сессии (спецификация qs-sessions): список сохранённых сессий демона
// workspaced слева, карта «стол → workspace» выбранной сессии справа. Открывается
// по событию show-sessions (цепочка sessions), Enter или клик загружает, Escape
// и клик вне окна закрывают, поле внизу сохраняет текущее состояние под именем.
// Захват ввода всплывающим окном невозможен: композитор отклоняет захват, если
// слой панели не получал ввода, а окно открывается с клавиатуры. Поэтому клавиши
// принимает слой панели (shell.qml берёт клавиатуру монопольно на время показа)
// и передаёт сюда через key(); поле имени рисуется из принятых нажатий.
import Quickshell
import QtQuick
import QtQuick.Layouts

PanelPopup {
    id: popup
    padX: 14
    padY: 10

    property var sessions: []
    property int current: 0
    // Текст поля имени новой сессии.
    property string nameText: ""
    readonly property var selected: sessions.length > current ? sessions[current] : null

    function open(item, list) {
        popup.sessions = list;
        popup.current = 0;
        popup.target = item;
        popup.anchor.updateAnchor();
        popup.nameText = "";
        popup.visible = true;
    }
    // Клавиша от слоя панели: Escape закрывает, стрелки выбирают, Enter загружает
    // выбранную сессию или, если введено имя, сохраняет текущее состояние.
    function key(ev) {
        ev.accepted = true;
        switch (ev.key) {
        case Qt.Key_Escape: popup.close(); break;
        case Qt.Key_Up: if (popup.current > 0) popup.current -= 1; break;
        case Qt.Key_Down: if (popup.current < popup.sessions.length - 1) popup.current += 1; break;
        case Qt.Key_Return: case Qt.Key_Enter:
            if (popup.nameText.trim() !== "") popup.save(); else popup.load();
            break;
        case Qt.Key_Backspace: popup.nameText = popup.nameText.slice(0, -1); break;
        default:
            if (ev.text && ev.text.length === 1 && ev.text >= " " && ev.text !== "\x7f") popup.nameText += ev.text;
            else ev.accepted = false;
        }
    }
    function close() { popup.visible = false; }
    function load() {
        if (!popup.selected) return;
        Wsd.sessionLoad(popup.selected.name);
        popup.close();
    }
    function save() {
        const name = popup.nameText.trim();
        if (name === "") return;
        Wsd.sessionSave(name);
        popup.nameText = "";
    }
    // Пометка: что поднимется сразу, что при переходе на стол, что по вызову.
    function mark(session, desktop, ws) {
        const d = session.desktops[desktop];
        if (!d || d.active !== ws) return "по вызову";
        return String(session.active_desktop) === desktop ? "сразу" : "при переходе";
    }
    function mapLines(session) {
        if (!session) return [];
        const out = [];
        for (let n = 1; n <= 8; n++) {
            const d = session.desktops[String(n)];
            if (!d || !d.workspaces || d.workspaces.length === 0) continue;
            out.push({ desktop: n, items: d.workspaces.map(w => ({ name: w, active: d.active === w, mark: mark(session, String(n), w) })) });
        }
        return out;
    }

    Connections {
        target: Wsd
        function onSessionsChanged() { if (popup.visible) popup.sessions = Wsd.sessions; }
    }
    Item {
        implicitWidth: layout.implicitWidth
        implicitHeight: layout.implicitHeight

        RowLayout {
            id: layout
            spacing: 24

            // --- Список сессий ---
            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignTop
                Text {
                    text: "Сессии"
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Repeater {
                    model: popup.sessions
                    Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool chosen: index === popup.current
                        Layout.fillWidth: true
                        implicitWidth: rowText.implicitWidth + 20
                        implicitHeight: rowText.implicitHeight + 8
                        radius: 8
                        color: chosen ? Theme.yellow : (rowMouse.containsMouse ? Theme.background : "transparent")
                        Text {
                            id: rowText
                            x: 10; y: 4
                            text: row.modelData.name + "   " + String(row.modelData.saved || "").replace("T", " ").substring(0, 16)
                            color: row.chosen ? "#000000" : Theme.yellow
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            font.bold: true
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: popup.current = row.index
                            onClicked: { popup.current = row.index; popup.load(); }
                        }
                    }
                }
                Text {
                    visible: popup.sessions.length === 0
                    text: "сохранённых сессий нет"
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                // Поле имени: Enter с введённым именем сохраняет текущее состояние.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    implicitWidth: 260
                    implicitHeight: 30
                    radius: 8
                    color: Theme.yellow
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        width: parent.width - 20
                        elide: Text.ElideLeft
                        text: popup.nameText === "" ? "сохранить как…" : popup.nameText + "▏"
                        color: popup.nameText === "" ? Qt.rgba(0, 0, 0, 0.6) : "#000000"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }

            // --- Карта выбранной сессии ---
            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignTop
                Text {
                    text: popup.selected ? ("Столы сессии " + popup.selected.name) : ""
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Repeater {
                    model: popup.mapLines(popup.selected)
                    RowLayout {
                        required property var modelData
                        spacing: 6
                        Text {
                            text: "стол " + modelData.desktop + ":"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                        }
                        Repeater {
                            model: modelData.items
                            Text {
                                required property var modelData
                                text: modelData.name + " (" + modelData.mark + ")"
                                color: modelData.active ? Theme.yellow : Theme.gray
                                font.family: Theme.fontFamily
                                font.pixelSize: 18
                                font.bold: modelData.active
                            }
                        }
                    }
                }
                Text {
                    visible: popup.selected && popup.mapLines(popup.selected).length === 0
                    text: "workspace в сессии нет"
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                Text {
                    visible: !!popup.selected
                    Layout.topMargin: 6
                    text: "Enter — загрузить (с именем — сохранить), Escape — закрыть"
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
