// Круговые шкалы CPU, RAM, GPU (спецификация qs-monitors): три плитки 100×100,
// значения и температурные классы из скриптов scripts/cpu, ram, gpu, cputemp,
// gputemp (JSON), обновление 3 с и 5 с, объём RAM раз в час.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import qs

Item {
    id: root
    width: Theme.tileWidth
    height: 100

    readonly property var classColors: ({ "t-low": "#39FF14", "t-mid": "#EAFF00", "t-high": "#FF9500", "t-crit": "#FF073A" })
    function colorOf(cls) { return classColors[cls] || Theme.gray; }

    property var cpu: ({ value: 0, class: "t-low" })
    property var ram: ({ value: 0, class: "t-low", total: 0 })
    property var gpu: ({ value: 0, class: "t-low" })
    property var cputemp: ({ value: 0, class: "t-low" })
    property var gputemp: ({ value: 0, class: "t-low" })
    property int ramTotal: 0

    // Скрипт метрики: одна строка JSON; при ошибке разбора прежнее значение сохраняется.
    component Metric: Item {
        id: m
        property string script
        property int interval: 3000
        signal result(var data)
        Process {
            id: proc
            command: [Quickshell.shellDir + "/scripts/" + m.script]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    try { m.result(JSON.parse(text)); } catch (e) { console.warn("gauges: " + m.script + ": не JSON:", text); }
                }
            }
        }
        Timer { interval: m.interval; running: true; repeat: true; onTriggered: proc.running = true }
    }
    Metric { script: "cpu";     interval: 3000; onResult: (d) => root.cpu = d }
    Metric { script: "ram";     interval: 3000; onResult: (d) => { root.ram = d; if (root.ramTotal === 0) root.ramTotal = d.total || 0; } }
    Metric { script: "gpu";     interval: 3000; onResult: (d) => root.gpu = d }
    Metric { script: "cputemp"; interval: 5000; onResult: (d) => root.cputemp = d }
    Metric { script: "gputemp"; interval: 5000; onResult: (d) => root.gputemp = d }
    // Объём RAM обновляется раз в час из того же ответа скрипта ram.
    Timer { interval: 3600000; running: true; repeat: true; onTriggered: root.ramTotal = root.ram.total || root.ramTotal }

    component Gauge: Tile {
        id: g
        property string name
        property color nameColor
        property string sub
        property color subColor
        property var metric
        width: 100
        height: 100

        // Координаты внутри Tile отсчитываются от внутреннего отступа (10 px от края);
        // по замечанию пользователя содержимое поднято на 12 px: заголовок у верхней
        // рамки, круг заканчивается за 8 px до нижней.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -6
            spacing: 4
            Text { text: g.name; color: g.nameColor; font.family: Theme.fontFamily; font.pointSize: Theme.pt(15.12); font.bold: true }
            Text { text: g.sub;  color: g.subColor;  font.family: Theme.fontFamily; font.pointSize: Theme.pt(15.12); font.bold: true }
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 100 - 6 - 70 - 12
            width: 70; height: 70
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 10
                    strokeColor: Qt.rgba(169/255, 177/255, 214/255, 0.15)
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathAngleArc { centerX: 35; centerY: 35; radiusX: 30; radiusY: 30; startAngle: -90; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: 10
                    strokeColor: root.colorOf(g.metric.class)
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathAngleArc { centerX: 35; centerY: 35; radiusX: 30; radiusY: 30; startAngle: -90; sweepAngle: 3.6 * Math.max(0, Math.min(100, g.metric.value)) }
                }
            }
            Text {
                anchors.centerIn: parent
                text: g.metric.value + "%"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
            }
        }
    }

    Gauge { x: 0;   name: "CPU"; nameColor: "#FF073A"; sub: root.cputemp.value + "°"; subColor: root.colorOf(root.cputemp.class); metric: root.cpu }
    Gauge { x: 110; name: "RAM"; nameColor: "#2E9FFF"; sub: root.ramTotal + "G";      subColor: Theme.foreground;                  metric: root.ram }
    Gauge { x: 220; name: "GPU"; nameColor: "#39FF14"; sub: root.gputemp.value + "°"; subColor: root.colorOf(root.gputemp.class); metric: root.gpu }
}
