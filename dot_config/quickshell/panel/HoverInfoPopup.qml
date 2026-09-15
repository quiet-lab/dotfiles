// Подсказка с подробностями (окна в плитках столов, приложения в лаунчере):
// справа от колонки на уровне элемента, не следует за указателем; при переходе
// между соседними элементами с тем же ключом меняется только содержимое.
import QtQuick
import QtQuick.Layouts

PanelPopup {
    id: info
    padX: 12
    padY: 8

    // Строки: первая — заголовок полужирным.
    property var lines: []
    property string key: ""

    function show(item, list, groupKey) {
        info.lines = list;
        hideTimer.stop();
        if (info.visible && groupKey !== "" && groupKey === info.key) return;
        info.key = groupKey;
        info.target = item;
        info.anchor.updateAnchor();
        info.visible = true;
    }
    function hide() { hideTimer.restart(); }

    Timer {
        id: hideTimer
        interval: 120
        onTriggered: { info.visible = false; info.key = ""; }
    }

    ColumnLayout {
        spacing: 2
        Repeater {
            model: info.lines
            Text {
                required property string modelData
                required property int index
                text: modelData
                color: Theme.yellow
                font.family: Theme.fontFamily
                font.pixelSize: 18
                font.bold: index === 0
            }
        }
    }
}
