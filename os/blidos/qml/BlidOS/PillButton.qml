import QtQuick

FocusScope {
    id: button
    property string text
    property bool primary: false
    signal activated()

    width: label.implicitWidth + Theme.px(56); height: Theme.px(56)
    activeFocusOnTab: true
    scale: activeFocus ? 1.05 : 1
    Behavior on scale { NumberAnimation { duration: 120 } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: button.primary ? Theme.accent : Theme.surfaceHi
        border.width: button.activeFocus ? Theme.px(3) : 0
        border.color: "white"
        Text {
            id: label
            anchors.centerIn: parent
            text: button.text
            color: Theme.text
            font.family: Theme.font; font.pixelSize: Theme.px(18); font.bold: true
        }
    }
    Keys.onReturnPressed: activated()
    Keys.onEnterPressed: activated()
    Keys.onSpacePressed: activated()
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: button.forceActiveFocus()
        onClicked: { button.forceActiveFocus(); button.activated() }
    }
}
