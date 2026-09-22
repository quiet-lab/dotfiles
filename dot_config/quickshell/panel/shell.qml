// Боковая панель сессии Hyprland (спецификация qs-shell): окно layer-shell
// у левого края DP-2 с зарезервированной зоной 330 px и колонкой плиток, повторяющей
// геометрию дашборда eww, и второе окно layer-shell — стопка уведомлений у нижнего
// края (спецификация qs-notifications). Здесь только окна и композиция колонки;
// плитки — в tiles/, всплывающие окна и карточки уведомлений — рядом, общие цвета
// и размеры — в Theme.qml.
// Запуск: `qs -c panel` (юнит quickshell-panel.service).
// Тема значков задаётся явно: qt6ct её не сообщает, и без pragma проверка наличия
// иконки в теме (hasThemeIcon) всегда отрицательна.
//@ pragma IconTheme breeze-dark
import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.tiles

ShellRoot {
    // Стопка всплывающих уведомлений — второе окно layer-shell панели, у нижнего
    // края монитора по центру (спецификация qs-notifications). Сервер уведомлений
    // и история живут в синглтоне NotificationService, окно только рисует стопку.
    Variants {
        model: Quickshell.screens.filter(s => s.name === "DP-2")

        NotificationStack {}
    }

    // Окно создаётся через Variants по списку экранов: при пропадании и возврате
    // монитора (DPMS, переподключение, временный выход FALLBACK) Quickshell
    // уничтожает окно старого экрана и создаёт новое для вернувшегося.
    Variants {
        model: Quickshell.screens.filter(s => s.name === "DP-2")

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData

            // Окно занимает всю полосу 330 px по высоте монитора, поэтому координаты
            // плиток внутри окна совпадают с экранными.
            anchors {
                left: true
                top: true
                bottom: true
            }
            implicitWidth: Theme.panelWidth
            exclusiveZone: Theme.panelWidth

            WlrLayershell.namespace: "panel"
            WlrLayershell.layer: WlrLayer.Top
            // Клавиатуру панель не просит: любой клик по слою в режиме OnDemand отдавал
            // бы ей ввод, а диспетчер фокуса окна у слоя клавиатуру не забирает. Режим
            // OnDemand включает только поле фильтра лаунчера на время работы с ним
            // (grabKeyboard / releaseKeyboard).
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Прозрачная поверхность: заливку несут плитки, промежутки остаются
            // прозрачными, и правило слоя panel в hyprland.lua размывает только плитки.
            color: "transparent"
            surfaceFormat.opaque: false

            // ---- Верхняя группа: питание, часы, погода (10…540) ----
            Power { x: Theme.margin; y: 10 }
            Clock { x: Theme.margin; y: 76 }
            Weather { x: Theme.margin; y: 325 }

            // ---- Средняя группа: шкалы, сеть, диски, избранное (704…1301) ----
            Gauges { x: Theme.margin; y: 704 }
            Network { x: Theme.margin; y: 816 }
            Disks { x: Theme.margin; y: 933 }
            Favorites { x: Theme.margin; y: 1178 }

            // ---- Нижняя группа: столы с уведомлениями, треем и раскладкой (1462…1820),
            // лаунчер (1830…2150). В правой колонке 36 px: уведомления на уровне
            // первого стола, под ними трей, внизу раскладка.
            Workspaces { id: workspacesTile; x: Theme.margin; y: 1462 }
            Notifications { x: 294; y: 1462 }
            Tray { x: 294; y: 1508 }
            Lang { x: 294; y: 1784 }
            Launcher { x: Theme.margin; y: 1830 }

            // Общие всплывающие окна; плитки обращаются к ним через синглтон Popups.
            TooltipPopup { id: tooltip }
            MenuPopup { id: menu }
            HoverInfoPopup { id: hoverInfo }
            // Окно выбора сессии открывается по событию демона workspaced на уровне
            // плиток столов. Клавиши принимает слой панели: на время показа он берёт
            // клавиатуру монопольно (у всплывающего окна без захвата ввода нет),
            // а при закрытии отпускает, и ввод возвращается окну.
            SessionsPopup { id: sessionsPopup }
            Item {
                id: sessionsKeys
                focus: sessionsPopup.visible
                Keys.onPressed: (ev) => sessionsPopup.key(ev)
            }
            Connections {
                target: Wsd
                function onShowSessions(list) {
                    sessionsPopup.open(workspacesTile, list);
                    panel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive;
                    sessionsKeys.forceActiveFocus();
                }
            }
            Connections {
                target: sessionsPopup
                function onVisibleChanged() { if (!sessionsPopup.visible) panel.releaseKeyboard(); }
            }

            // Попросить клавиатуру по требованию (перед кликом в поле фильтра) и отдать
            // её обратно окнам: слой перестаёт просить фокус, и композитор возвращает
            // его последнему окну.
            function grabKeyboard() { panel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand; }
            function releaseKeyboard() { panel.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None; }

            Component.onCompleted: {
                Popups.panel = panel;
                Popups.tooltip = tooltip;
                Popups.menu = menu;
                Popups.hoverInfo = hoverInfo;
                Popups.sessions = sessionsPopup;
            }
        }
    }
}
