import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: field
    width: Theme.px(480)
    color: Theme.text
    placeholderTextColor: Theme.dim
    selectionColor: Theme.accent
    font.family: Theme.font; font.pixelSize: Theme.px(22)
    leftPadding: Theme.px(18); rightPadding: Theme.px(18); topPadding: Theme.px(14); bottomPadding: Theme.px(14)
    background: Rectangle {
        radius: Theme.px(12)
        color: Theme.surface
        border.width: field.activeFocus ? Theme.px(3) : Theme.px(1)
        border.color: field.activeFocus ? "white" : Theme.surfaceHi
    }
}
