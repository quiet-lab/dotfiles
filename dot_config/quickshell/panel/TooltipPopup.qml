// Подсказка при наведении: одна на панель. show(item, text) показывает её справа
// от колонки на уровне item, hide(item) скрывает.
import QtQuick
import qs.common

PanelPopup {
    id: tip
    padX: 8
    padY: 4
    property string text: ""

    // Элемент, которому подсказка принадлежит сейчас. Скрыть её может только он
    // сам: Qt доставляет наведение на новый элемент раньше, чем уход с прежнего
    // (проверено 22.09.2026 по журналу панели), поэтому уход с прежнего значка
    // приходит, когда подсказку уже показал соседний. Без проверки владельца
    // такой уход гасил подсказку под указателем, и она больше не появлялась:
    // указатель стоит внутри нового значка, второго наведения не будет.
    property Item owner: null

    function show(item, text) {
        tip.owner = item;
        tip.text = text;
        if (tip.target !== item) {
            tip.target = item;
            tip.anchor.updateAnchor();
        }
        tip.visible = true;
    }
    function hide(item) {
        if (item !== tip.owner) return;
        tip.owner = null;
        tip.visible = false;
    }

    // Элемент-владелец исчез (список плитки перестроился под указателем): якоря
    // у подсказки больше нет, и она скрывается.
    onTargetChanged: if (!tip.target) tip.hide(tip.owner);

    Text {
        text: tip.text
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
