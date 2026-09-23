// Подсказка с подробностями (окна в плитках столов, приложения в лаунчере):
// справа от колонки на уровне элемента, не следует за указателем; при переходе
// между соседними элементами с тем же ключом меняется только содержимое.
import QtQuick
import QtQuick.Layouts
import qs.common

PanelPopup {
    id: info
    padX: 12
    padY: 8

    // Строки: первая — заголовок полужирным.
    property var lines: []
    property string key: ""

    // Элемент, которому подсказка принадлежит сейчас. Скрыть её может только он
    // сам: Qt доставляет наведение на новый элемент раньше, чем уход с прежнего
    // (проверено 22.09.2026 по журналу панели), а значки в ряду стоят вплотную,
    // поэтому уход с прежнего значка приходит, когда подсказку уже показал
    // соседний. Без проверки владельца такой уход гасил подсказку под
    // указателем, и она больше не появлялась: указатель стоит внутри нового
    // значка, второго наведения не будет.
    property Item owner: null

    function show(item, list, groupKey) {
        info.owner = item;
        info.lines = list;
        if (info.visible && groupKey !== "" && groupKey === info.key) return;
        info.key = groupKey;
        info.target = item;
        info.anchor.updateAnchor();
        info.visible = true;
    }
    function hide(item) {
        if (item !== info.owner) return;
        info.owner = null;
        info.visible = false;
        info.key = "";
    }

    // Элемент-якорь исчез (список плитки перестроился под указателем): якоря
    // у подсказки больше нет, и она скрывается.
    onTargetChanged: if (!info.target) info.hide(info.owner);

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
