// Подсказка при наведении: одна на панель. show(item, text) показывает её справа
// от колонки на уровне item, hide() скрывает.
import QtQuick

PanelPopup {
    id: tip
    padX: 8
    padY: 4
    property string text: ""

    // Скрытие выполняется не в самом обработчике ухода указателя, а сразу после
    // того, как разобрано текущее событие мыши: при переходе между соседними
    // значками уход с одного и наведение на другой приходят одним событием,
    // и подсказка не должна из-за этого пропадать и появляться заново. Отсрочки
    // по времени здесь нет — Qt.callLater ждёт не срока, а конца разбора события.
    property bool hidePending: false

    function show(item, text) {
        tip.hidePending = false;
        tip.text = text;
        tip.target = item;
        tip.anchor.updateAnchor();
        tip.visible = true;
    }
    function hide() {
        tip.hidePending = true;
        Qt.callLater(tip.applyHide);
    }
    function applyHide() {
        if (!tip.hidePending) return;
        tip.hidePending = false;
        tip.visible = false;
    }

    Text {
        text: tip.text
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
