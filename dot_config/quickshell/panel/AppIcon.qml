// Иконка приложения с перебором источников: sources — список URL по убыванию
// приоритета (иконка темы, файлы вне темы, generic); при ошибке загрузки
// берётся следующий, так что ячейка не остаётся пустой.
import QtQuick

Image {
    id: icon
    property var sources: []
    property int index: 0

    source: sources.length > index ? sources[index] : ""
    sourceSize: Qt.size(width * 2, height * 2)
    fillMode: Image.PreserveAspectFit
    asynchronous: false
    // Предупреждения «Cannot open» для отсутствующих файлов-кандидатов ожидаемы.

    onSourcesChanged: index = 0
    // Переход к следующему кандидату откладывается: смена индекса внутри
    // обработчика статуса создаёт петлю привязки source.
    onStatusChanged: if (status === Image.Error && index < sources.length - 1) Qt.callLater(() => index += 1)
}
