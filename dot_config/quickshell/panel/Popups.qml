// Общие всплывающие окна панели. shell.qml создаёт экземпляры и кладёт их сюда,
// плитки обращаются к ним через синглтон: Popups.tooltip.show(item, "текст"),
// Popups.menu.open(item, пункты), Popups.hoverInfo.show(item, строки, ключ).
// Меню одно на панель: открытие нового закрывает предыдущее.
pragma Singleton
import QtQuick

QtObject {
    property var tooltip: null
    property var menu: null
    property var hoverInfo: null
    // Окно панели: у него плитки просят отдать фокус клавиатуры (releaseKeyboard).
    property var panel: null
}
