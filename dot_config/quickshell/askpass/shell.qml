// Окно ввода пароля sudo (спецификация qs-askpass): отдельная конфигурация
// Quickshell, которую на время запроса запускает обёртка
// ~/.local/bin/handmade-scripts/sudo-askpass командой `qs -c askpass`.
// Оформление взято у панели: каталог panel рядом — символическая ссылка
// на ../panel, поэтому Theme и Tile подключаются модулем qs.panel, а цвета,
// шрифт, рамка и отступы не копируются.
// Пароль в журнал не попадает: окно отдаёт его только в именованный канал,
// путь к которому приходит переменной окружения ASKPASS_FIFO, и только через
// stdin дочернего процесса, поэтому в списке процессов его тоже нет.
// Первая строка в канале — ответ окна: «P» и пароль либо «C» при отмене.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.panel

ShellRoot {
    id: root

    readonly property string fifo: Quickshell.env("ASKPASS_FIFO")
    readonly property string message: Quickshell.env("ASKPASS_MESSAGE") || "Команда запрашивает права root"
    // Окно нужно на мониторе с курсором; в Hyprland это монитор в фокусе.
    readonly property string monitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    // Ответ окна, который дочерний процесс перепишет в канал.
    property string answer: ""

    // Ответ уходит в канал через stdin `cat`, затем тот же процесс снимает
    // Quickshell: своей команды выхода у версии 0.3.1 нет, а обёртке нужно,
    // чтобы окно исчезло сразу после ответа.
    Process {
        id: writer
        command: ["sh", "-c", "cat > \"$1\"; kill \"$2\"", "sh",
                  root.fifo, String(Quickshell.processId)]
        stdinEnabled: true
        onStarted: {
            writer.write(root.answer + "\n");
            // Закрытый stdin — признак конца ввода для `cat`.
            writer.stdinEnabled = false;
        }
    }

    function send(text) {
        if (writer.running)
            return;
        root.answer = text;
        writer.running = true;
    }
    function accept() {
        if (field.text.length > 0)
            root.send("P" + field.text);
    }
    function cancel() { root.send("C"); }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === root.monitorName) || null

        // Слой overlay лежит выше обычных окон, ввод забирается монопольно,
        // поэтому поле получает клавиатуру сразу и не отдаёт её. Демон
        // workspaced окна слоёв не видит и в workspace их не принимает.
        WlrLayershell.namespace: "askpass"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        // Ни к одному краю окно не привязано, поэтому композитор ставит его
        // по центру монитора; зона у края не резервируется.
        exclusiveZone: 0

        // Поверхность прозрачная: заливку несёт плитка, как в панели.
        color: "transparent"
        surfaceFormat.opaque: false
        implicitWidth: dialog.width
        implicitHeight: dialog.height

        Tile {
            id: dialog
            width: 760
            height: body.implicitHeight + 2 * (Theme.tilePadding + 1)

            Column {
                id: body
                width: parent.width
                spacing: Theme.gap

                Text {
                    text: "SUDO"
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.pt(Theme.titleSize)
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: root.message
                    color: Theme.foreground
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                }

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 6
                    color: Theme.black
                    border.width: 1
                    border.color: field.activeFocus ? Theme.yellow : Theme.gray

                    TextInput {
                        id: field
                        anchors.fill: parent
                        anchors.leftMargin: Theme.gap
                        anchors.rightMargin: Theme.gap + eye.width + Theme.gap
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: eye.shown ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        color: Theme.foreground
                        selectionColor: Theme.yellow
                        selectedTextColor: "#000000"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        clip: true
                        focus: true
                        Keys.onEscapePressed: root.cancel()
                        Keys.onReturnPressed: root.accept()
                        Keys.onEnterPressed: root.accept()
                    }

                    // Переключатель показа набранного пароля.
                    Text {
                        id: eye
                        property bool shown: false
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.gap
                        anchors.verticalCenter: parent.verticalCenter
                        text: shown ? "󰈉" : "󰈈"
                        color: eyeMouse.containsMouse ? Theme.yellow : Theme.gray
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        MouseArea {
                            id: eyeMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Клавиатура остаётся у поля: показ переключается,
                            // не прерывая набор.
                            onClicked: { eye.shown = !eye.shown; field.forceActiveFocus(); }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "Enter — ввод, Escape — отмена, значок справа показывает набранное"
                    color: Theme.gray
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.pt(Theme.titleSize)
                }
            }
        }

        Component.onCompleted: field.forceActiveFocus()
    }
}
