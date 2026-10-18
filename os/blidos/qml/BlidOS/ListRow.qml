import QtQuick

// One line in a settings list: title on the left, detail on the right.
FocusScope {
    id: row
    property string title
    property string detail
    property url iconSource
    signal activated()

    width: parent ? parent.width : Theme.px(800)
    height: Theme.px(72)
    activeFocusOnTab: true
    scale: activeFocus ? 1.015 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: Theme.px(12)
        color: row.activeFocus ? Theme.surfaceHi : Theme.surface
        Behavior on color { ColorAnimation { duration: 140 } }
        border.width: row.activeFocus ? Theme.px(3) : 0
        border.color: "white"
        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.px(24)
            spacing: Theme.px(16)
            Image {
                visible: row.iconSource != ""
                width: Theme.px(28); height: width
                anchors.verticalCenter: parent.verticalCenter
                source: row.iconSource
                sourceSize: Qt.size(width, height)
            }
            Text {
                text: row.title
                color: Theme.text
                font.family: Theme.font; font.pixelSize: Theme.px(20); font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: Theme.px(24)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.45
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: row.detail
            color: Theme.dim
            font.family: Theme.font; font.pixelSize: Theme.px(17)
        }
    }
    Keys.onReturnPressed: activated()
    Keys.onEnterPressed: activated()
    Keys.onSpacePressed: activated()
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: row.forceActiveFocus()
        onClicked: { row.forceActiveFocus(); row.activated() }
    }
}
