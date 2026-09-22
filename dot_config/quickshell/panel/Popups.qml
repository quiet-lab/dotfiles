// Общие всплывающие окна панели. shell.qml создаёт экземпляры и кладёт их сюда,
// плитки обращаются к ним через синглтон: Popups.tooltip.show(item, "текст"),
// Popups.menu.open(item, пункты), Popups.hoverInfo.show(item, строки, ключ).
// Скрывают подсказку hide(item) тем же элементом, который её показал: уход
// с прежнего элемента приходит позже наведения на соседний и подсказку,
// принадлежащую уже соседу, не гасит.
// Меню одно на панель: открытие нового закрывает предыдущее.
pragma Singleton
import QtQuick

QtObject {
    property var tooltip: null
    property var menu: null
    property var hoverInfo: null
    property var sessions: null
    // Окно панели: у него плитки просят отдать фокус клавиатуры (releaseKeyboard).
    property var panel: null
}
