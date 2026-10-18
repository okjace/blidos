import QtQuick

Rectangle {
    property string name
    property int colorIndex
    width: Theme.px(104); height: width; radius: width / 2
    color: Theme.profileColor(colorIndex)
    Text {
        anchors.centerIn: parent
        text: (parent.name || "?").charAt(0).toUpperCase()
        color: "white"
        font.family: Theme.font; font.pixelSize: parent.width * 0.42; font.bold: true
    }
}
