// Плитка часов (спецификация qs-clock-calendar): часы, дата в ru_RU и календарь,
// сетку которого строит сама плитка (design D10). Размеры и отступы — из clock.scss.
import Quickshell
import QtQuick
import qs

Tile {
    id: tile
    height: 239

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // --- Состояние календаря ---
    // Показываемый месяц (год, месяц 0…11) и выбранный день (строка ГГГГ-ММ-ДД или "").
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property string selected: ""
    // Сегодняшняя дата обновляется при смене суток по тику часов.
    property string today: dayKey(new Date())
    onTodayChanged: grid.rebuild()

    readonly property var monthNames: ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
        "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
    readonly property var dayNames: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    readonly property var shortDays: ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    readonly property var shortMonths: ["янв", "фев", "мар", "апр", "мая", "июн",
        "июл", "авг", "сен", "окт", "ноя", "дек"]

    function dayKey(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    }
    function shiftMonth(n) {
        const d = new Date(viewYear, viewMonth + n, 1);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
        grid.rebuild();
    }
    function goToday() {
        const d = new Date();
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
        grid.rebuild();
    }
    function pad2(n) { return String(n).padStart(2, "0"); }

    Connections {
        target: clock
        function onDateChanged() {
            const k = tile.dayKey(clock.date);
            if (k !== tile.today) tile.today = k;
        }
    }

    // Поля строки времени и шапки календаря: 27 px от левой рамки до цифр сетки.
    readonly property int headLeft: 16
    readonly property int headRight: 18

    // --- Строка времени и даты ---
    Item {
        id: head
        x: tile.headLeft
        width: parent.width - tile.headLeft - tile.headRight
        height: timeRow.implicitHeight

        Row {
            id: timeRow
            Text { text: tile.pad2(clock.date.getHours()); color: Theme.yellow; font.family: Theme.fontFamily; font.pointSize: Theme.pt(30.8); font.bold: true }
            Text { text: ":"; color: Theme.gray; font.family: Theme.fontFamily; font.pointSize: Theme.pt(30.8); leftPadding: 4; rightPadding: 4 }
            Text { text: tile.pad2(clock.date.getMinutes()); color: Theme.yellow; font.family: Theme.fontFamily; font.pointSize: Theme.pt(30.8); font.bold: true }
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: timeRow.bottom
            anchors.bottomMargin: 4
            text: tile.shortDays[clock.date.getDay()] + ", " + tile.pad2(clock.date.getDate()) + " " + tile.shortMonths[clock.date.getMonth()]
            color: "#9D7A49"
            font.family: Theme.fontFamily
            font.pointSize: Theme.pt(21.84)
        }
        MouseArea {
            anchors.fill: parent
            onClicked: tile.goToday()
        }
    }

    // --- Шапка календаря: ‹ Месяц ›  ‹ Год › ---
    Item {
        id: calHead
        x: 15
        y: head.y + head.height + 6
        width: parent.width - 15 - 17
        height: 20

        component Arrow: Text {
            property var action
            color: hover.containsMouse ? Theme.blue : Theme.magenta
            font.family: Theme.fontFamily
            font.pointSize: Theme.pt(14.7)
            font.bold: true
            MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: parent.action() }
        }
        component Title: Text {
            color: Theme.wallGreen
            font.family: Theme.fontFamily
            font.pointSize: Theme.pt(14.7)
            font.bold: true
            leftPadding: 6; rightPadding: 6
        }

        Row {
            anchors.left: parent.left
            Arrow { text: "‹"; action: () => tile.shiftMonth(-1) }
            Title { text: tile.monthNames[tile.viewMonth] }
            Arrow { text: "›"; action: () => tile.shiftMonth(1) }
        }
        Row {
            anchors.right: parent.right
            Arrow { text: "‹"; action: () => tile.shiftMonth(-12) }
            Title { text: String(tile.viewYear) }
            Arrow { text: "›"; action: () => tile.shiftMonth(12) }
        }
    }

    // --- Сетка: названия дней и шесть строк по семь ячеек ---
    Column {
        id: grid
        x: 3
        y: calHead.y + calHead.height + 5
        width: parent.width - 3 - 9
        readonly property real cell: width / 7
        property var days: []

        function rebuild() {
            const first = new Date(tile.viewYear, tile.viewMonth, 1);
            // Понедельник — первый день недели.
            const lead = (first.getDay() + 6) % 7;
            const start = new Date(tile.viewYear, tile.viewMonth, 1 - lead);
            const list = [];
            for (let i = 0; i < 42; i++) {
                const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
                list.push({ n: d.getDate(), key: tile.dayKey(d), other: d.getMonth() !== tile.viewMonth });
            }
            days = list;
        }
        Component.onCompleted: rebuild()

        Row {
            Repeater {
                model: tile.dayNames
                Text {
                    required property string modelData
                    width: grid.cell; height: 20
                    text: modelData
                    color: Theme.white
                    font.family: Theme.fontFamily; font.pointSize: Theme.pt(14.7); font.bold: true
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }
        }
        Repeater {
            model: 6
            Row {
                id: row
                required property int index
                Repeater {
                    model: 7
                    Item {
                        id: cellItem
                        required property int index
                        readonly property var day: grid.days[row.index * 7 + index] || { n: 0, key: "", other: true }
                        readonly property bool isToday: day.key === tile.today
                        readonly property bool isSel: day.key === tile.selected
                        width: grid.cell; height: 20

                        Rectangle {
                            visible: cellItem.isToday
                            anchors.centerIn: parent
                            width: 20; height: 20; radius: 10
                            color: Theme.yellow
                        }
                        Text {
                            anchors.centerIn: parent
                            text: cellItem.day.n
                            color: cellItem.isSel ? Theme.white : cellItem.isToday ? "#000000" : cellItem.day.other ? "#705834" : Theme.yellow
                            font.family: Theme.fontFamily
                            font.pointSize: Theme.pt(cellItem.isToday ? 16.7 : 14.7)
                            font.bold: cellItem.isToday
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: tile.selected = cellItem.day.key
                        }
                    }
                }
            }
        }
    }
}
