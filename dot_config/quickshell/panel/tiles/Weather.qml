// Плитка погоды (спецификация qs-weather): сводка и прогноз на 3 дня из
// scripts/weather (JSON), обновление раз в 30 минут, глифы и цвета по коду WWO.
import Quickshell
import Quickshell.Io
import QtQuick
import qs

Tile {
    id: tile
    height: 215

    property var data: null
    property bool loaded: false

    Process {
        id: proc
        command: [Quickshell.shellDir + "/scripts/weather"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                tile.loaded = true;
                try {
                    const d = JSON.parse(text);
                    tile.data = d.error ? null : d;
                } catch (e) { tile.data = null; console.warn("weather: не JSON:", text); }
            }
        }
    }
    Timer { interval: 1800000; running: true; repeat: true; onTriggered: proc.running = true }

    // Глиф и цвет по коду погоды WWO.
    function kind(code) {
        switch (code) {
        case 113: return "clear";
        case 116: return "partly";
        case 119: case 122: return "overcast";
        case 143: case 248: case 260: return "fog";
        case 176: case 263: case 266: case 281: case 284: case 293: case 296: case 299: case 302:
        case 305: case 308: case 311: case 314: case 350: case 353: case 356: case 359: case 374: case 377: return "rain";
        case 179: case 182: case 185: case 227: case 230: case 317: case 320: case 323: case 326:
        case 329: case 332: case 335: case 338: case 362: case 365: case 368: case 371: return "snow";
        case 200: case 386: case 389: case 392: case 395: return "storm";
        default: return "unknown";
        }
    }
    readonly property var glyphs: ({ clear: "󰖙", partly: "󰖕", overcast: "󰖐", fog: "󰖑", rain: "󰖗", snow: "󰖘", storm: "󰙾", unknown: "󰼱" })
    readonly property var colors: ({ clear: "#FFFF00", partly: "#FFC66D", overcast: "#A0A0A0", fog: "#D0D0D0", rain: "#0080FF", snow: "#FFFFFF", storm: "#A020F0", unknown: Theme.gray })
    function glyph(code) { return glyphs[kind(code)]; }
    function tint(code) { return colors[kind(code)]; }

    // Заполнитель до первого ответа и метка при отсутствии данных.
    Text {
        visible: tile.data === null
        x: 14; y: 4
        text: tile.loaded ? "нет данных" : "…"
        color: Theme.gray
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Item {
        visible: tile.data !== null
        anchors.fill: parent

        // Сводка: глиф, температура, город.
        Item {
            id: now
            x: 14
            width: parent.width - 14 - 18
            height: temp.implicitHeight
            Text {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                text: tile.data ? tile.glyph(tile.data.code) : ""
                color: tile.data ? tile.tint(tile.data.code) : Theme.gray
                font.family: Theme.fontFamily
                font.pointSize: Theme.pt(36.4)
            }
            Text {
                id: temp
                x: icon.width + 20
                text: tile.data ? tile.data.temp + "°" : ""
                color: Theme.yellow
                font.family: Theme.fontFamily
                font.pointSize: Theme.pt(30.8)
                font.bold: true
            }
            Text {
                anchors.right: parent.right
                anchors.bottom: temp.bottom
                anchors.bottomMargin: 4
                text: tile.data ? tile.data.city : ""
                color: "#9D7A49"
                font.family: Theme.fontFamily
                font.pointSize: Theme.pt(21.84)
            }
        }

        // Прогноз: шапка частей суток и три дня.
        // Ширина и шаг строк подобраны по замеру снимка: отступы справа и снизу до
        // содержимого равны отступу слева до названий дней (24 px от рамки).
        Column {
            id: forecast
            x: 14
            y: now.y + now.height + 10
            width: parent.width - 14 - 5
            spacing: 12.67
            readonly property real dayWidth: 24 + 12
            readonly property real partWidth: (width - dayWidth) / 4

            Row {
                Item { width: forecast.dayWidth; height: 1 }
                Repeater {
                    model: ["󰽥", "󰖜", "󰖙", "󰖛"]
                    Item {
                        required property string modelData
                        width: forecast.partWidth; height: 26
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: Theme.white
                            font.family: Theme.fontFamily
                            font.pointSize: Theme.pt(22.4)
                        }
                    }
                }
            }
            Repeater {
                model: tile.data ? tile.data.days : []
                Row {
                    id: dayRow
                    required property var modelData
                    Text {
                        width: forecast.dayWidth
                        text: dayRow.modelData.name
                        color: Theme.white
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.pt(17.5)
                        font.bold: true
                    }
                    Repeater {
                        model: dayRow.modelData.parts
                        Item {
                            id: part
                            required property var modelData
                            width: forecast.partWidth; height: 24
                            Row {
                                anchors.centerIn: parent
                                visible: part.modelData !== null
                                spacing: 1
                                Text {
                                    text: part.modelData ? part.modelData.temp + "°" : ""
                                    color: Theme.yellow
                                    font.family: Theme.fontFamily
                                    font.pointSize: Theme.pt(17.5)
                                }
                                Text {
                                    text: part.modelData ? tile.glyph(part.modelData.code) : ""
                                    color: part.modelData ? tile.tint(part.modelData.code) : Theme.gray
                                    font.family: Theme.fontFamily
                                    font.pointSize: Theme.pt(19.6)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
