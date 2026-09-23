// Общие цвета, шрифты и размеры панели (Tokyo Night, значения из eww.scss).
// Все размеры в пикселях: панель рассчитана на монитор DP-2 3840×2160.
pragma Singleton
import QtQuick

QtObject {
    // Палитра Tokyo Night.
    readonly property color background: "#1A1B26"
    readonly property color foreground: "#A9B1D6"
    readonly property color black:      "#24283B"
    readonly property color gray:       "#565F89"
    readonly property color red:        "#F7768E"
    readonly property color green:      "#73DACA"
    readonly property color yellow:     "#E0AF68"
    readonly property color wallGreen:  "#A8E040"
    readonly property color blue:       "#7AA2F7"
    readonly property color magenta:    "#BB9AF7"
    readonly property color cyan:       "#7DCFFF"
    readonly property color white:      "#FFFFFF"

    // Плитка: чёрная заливка с непрозрачностью 0.9 (правила слоя Hyprland не задают
    // непрозрачность слоя, поэтому альфу несёт заливка; промежутки прозрачные и
    // лежат ниже порога ignore_alpha правила слоя panel), жёлтая рамка 1 px,
    // скругление 12 px, внутренний отступ 9 px (плюс рамка — 10 px до содержимого).
    readonly property color tileBg:     Qt.rgba(0, 0, 0, 0.9)
    readonly property color tileBorder: yellow
    readonly property int   tileRadius: 12
    readonly property int   tilePadding: 9
    // Полоса табов плитки активного стола: тёмно-серый Tokyo Night (`black`)
    // с непрозрачностью 0.5 поверх чёрной заливки плитки — полоса лишь чуть
    // светлее ряда окон (решение пользователя 23.09.2026). Активный таб
    // не покрыт полосой и остаётся цвета заливки, поэтому сливается с рядом
    // окон под ним.
    readonly property color tabBarBg:   Qt.rgba(0x24 / 255, 0x28 / 255, 0x3B / 255, 0.5)
    // Всплывающие окна: та же заливка и рамка, скругление 8 px.
    readonly property int   popupRadius: 8

    // Шрифты.
    readonly property string fontFamily: "IosevkaTermSlab NF"
    readonly property var    fontFallbacks: ["MesloLGMDZ Nerd Font", "monospace"]
    readonly property int    fontSize: 14
    readonly property real   titleSize: 13.3
    // Дробные размеры из eww задаются в пунктах: font.pixelSize принимает только
    // целые, а при 96 dpi 1 px = 0.75 pt, так что размер совпадает точно.
    function pt(px) { return px * 0.75; }

    // Геометрия колонки: левый отступ и зазор между плитками.
    readonly property int margin: 10
    readonly property int gap: 10
    readonly property int panelWidth: 330
    readonly property int tileWidth: 320
}
