pragma Singleton
import QtQuick

// Colors and sizes. Everything scales with the screen height (designed at 1080p).
QtObject {
    readonly property real s: Math.max(0.5, (Qt.application.screens.length ? Qt.application.screens[0].height : 1080) / 1080)
    function px(v) { return Math.round(v * s) }

    readonly property color bgTop: "#16203A"
    readonly property color bgBottom: "#05070D"
    readonly property color surface: "#1C2333"
    readonly property color surfaceHi: "#2A3348"
    readonly property color accent: "#4F7CFF"
    readonly property color play: "#01875F"
    readonly property color text: "#FFFFFF"
    readonly property color dim: "#B3FFFFFF"
    readonly property color error: "#FF6B6B"
    readonly property var profileColors: ["#4F7CFF", "#FF6B6B", "#2EC4B6", "#FFB627", "#9B5DE5", "#00BBF9"]
    readonly property string font: "Noto Sans"

    function profileColor(i) { return profileColors[(i || 0) % profileColors.length] }
    function icon(name) { return Qt.resolvedUrl("icons/" + name + ".svg") }
}
