// Подсказка при наведении: одна на панель. show(item, text) показывает её справа
// от колонки на уровне item после короткой задержки, hide() скрывает.
import QtQuick

PanelPopup {
    id: tip
    padX: 8
    padY: 4
    property string text: ""

    function show(item, text) {
        tip.target = item;
        tip.text = text;
        delay.restart();
    }
    function hide() {
        delay.stop();
        tip.visible = false;
    }

    Timer {
        id: delay
        interval: 350
        onTriggered: tip.visible = true
    }

    Text {
        text: tip.text
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
