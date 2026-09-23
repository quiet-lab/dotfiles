// Меню DBusMenu элемента трея собственной отрисовкой (design D6): пункты из
// QsMenuOpener, подменю открываются справа от пункта тем же компонентом,
// флажки и переключатели показываются жёлтым маркером, разделители — линией.
// Закрывается после выбора пункта и кликом вне меню (grabFocus).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.common

PanelPopup {
    id: menu
    padX: 4
    padY: 8
    grabFocus: true

    // Меню (QsMenuHandle) и корневое меню, которое закрывает всю цепочку.
    property var handle: null
    property var rootMenu: menu

    function open(item, menuHandle) {
        menu.handle = menuHandle;
        menu.target = item;
        menu.anchor.updateAnchor();
        menu.visible = true;
    }
    function closeAll() { rootMenu.visible = false; }
    onVisibleChanged: if (!visible) closeSub()

    // Подменю создаётся через Loader: QML не допускает прямого вложения типа в себя.
    function openSub(row, handle) {
        subLoader.active = true;
        subLoader.item.open(row, handle);
    }
    function closeSub() { if (subLoader.item) subLoader.item.visible = false; }

    QsMenuOpener {
        id: opener
        menu: menu.handle
    }

    // Подменю: тот же компонент, привязанный к правому краю этого меню.
    Loader {
        id: subLoader
        active: false
        source: "TrayMenuPopup.qml"
        onLoaded: {
            item.rootMenu = Qt.binding(() => menu.rootMenu);
            item.anchorX = Qt.binding(() => menu.implicitWidth);
        }
    }

    ColumnLayout {
        spacing: 0
        Repeater {
            model: opener.children
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool sep: modelData.isSeparator
                readonly property bool checked: modelData.checkState === Qt.Checked
                Layout.fillWidth: true
                implicitWidth: sep ? 0 : label.implicitWidth + 24 + (row.modelData.hasChildren ? 22 : 0)
                implicitHeight: sep ? 9 : label.implicitHeight + 12

                Rectangle {
                    visible: row.sep
                    x: 4; y: 4
                    width: parent.width - 8; height: 1
                    color: Theme.yellow
                }
                Rectangle {
                    visible: !row.sep
                    anchors.fill: parent
                    radius: 6
                    color: mouse.containsMouse && row.modelData.enabled ? Theme.yellow : "transparent"

                    Row {
                        x: 4; y: 6
                        spacing: 0
                        Rectangle {
                            visible: row.checked
                            width: 10; height: 10; radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: mouse.containsMouse ? "#000000" : Theme.yellow
                        }
                        Item { width: row.checked ? 8 : 0; height: 1 }
                        Text {
                            id: label
                            text: row.modelData.text
                            color: !row.modelData.enabled ? Theme.gray : mouse.containsMouse ? "#000000" : Theme.yellow
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                        }
                    }
                    Text {
                        visible: row.modelData.hasChildren
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: mouse.containsMouse ? "#000000" : Theme.yellow
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.modelData.enabled
                        onEntered: {
                            if (row.modelData.hasChildren) menu.openSub(row, row.modelData);
                            else menu.closeSub();
                        }
                        onClicked: {
                            if (row.modelData.hasChildren) { menu.openSub(row, row.modelData); return; }
                            menu.closeAll();
                            row.modelData.triggered();
                        }
                    }
                }
            }
        }
    }
}
