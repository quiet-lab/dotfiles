// Базовая плитка колонки: заливка, рамка и скругление из Theme; содержимое
// кладётся в `content` с отступом tilePadding от рамки.
import QtQuick

Rectangle {
    id: tile

    default property alias content: inner.data
    // Заголовок плитки («СЕТЬ», «ДИСКИ» и т. п.); пустая строка — без заголовка.
    property string title: ""

    width: Theme.tileWidth
    color: Theme.tileBg
    border.color: Theme.tileBorder
    border.width: 1
    radius: Theme.tileRadius

    Text {
        id: titleLabel
        visible: tile.title !== ""
        x: Theme.tilePadding + 1
        y: Theme.tilePadding + 1
        text: tile.title
        color: Theme.gray
        font.family: Theme.fontFamily
        font.pointSize: Theme.pt(Theme.titleSize)
        font.bold: true
    }

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: Theme.tilePadding + 1
        anchors.topMargin: Theme.tilePadding + 1 + (titleLabel.visible ? titleLabel.height + 6 : 0)
    }
}
