import QtQuick

// A focusable tile for the home screen rows: app banner/icon, or icon + title + subtitle.
FocusScope {
    id: tile
    property string title
    property string subtitle
    property url iconSource
    property url imageSource
    property color fill: Theme.surface
    property bool dimmed: false
    signal activated()

    width: Theme.px(208); height: Theme.px(118)
    activeFocusOnTab: true
    scale: activeFocus ? 1.08 : 1
    z: activeFocus ? 1 : 0
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: Theme.px(14)
        color: tile.fill
        opacity: tile.dimmed ? 0.5 : 1
        border.width: tile.activeFocus ? Theme.px(3) : 0
        border.color: "white"

        Image {
            id: image
            visible: tile.imageSource != ""
            anchors.fill: parent; anchors.margins: Theme.px(18)
            anchors.bottomMargin: tile.title ? Theme.px(40) : Theme.px(18)
            source: tile.imageSource
            fillMode: Image.PreserveAspectFit
            sourceSize.height: Theme.px(96)
            asynchronous: true
        }
        Image {
            visible: !image.visible && tile.iconSource != ""
            x: Theme.px(18); y: Theme.px(16)
            width: Theme.px(32); height: width
            source: tile.iconSource
            sourceSize: Qt.size(width, height)
        }
        Column {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: Theme.px(14); anchors.leftMargin: Theme.px(18)
            spacing: Theme.px(2)
            Text {
                width: parent.width
                text: tile.title
                color: Theme.text
                font.family: Theme.font; font.pixelSize: Theme.px(17); font.bold: true
                elide: Text.ElideRight
                horizontalAlignment: image.visible ? Text.AlignHCenter : Text.AlignLeft
            }
            Text {
                width: parent.width
                visible: text !== "" && !image.visible
                text: tile.subtitle
                color: Theme.dim
                font.family: Theme.font; font.pixelSize: Theme.px(13)
                elide: Text.ElideRight
            }
        }
    }
    Keys.onReturnPressed: activated()
    Keys.onEnterPressed: activated()
    Keys.onSpacePressed: activated()
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: tile.forceActiveFocus()
        onClicked: { tile.forceActiveFocus(); tile.activated() }
    }
}
