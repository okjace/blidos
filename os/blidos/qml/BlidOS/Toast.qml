import QtQuick

Rectangle {
    id: toast
    property alias text: label.text
    function show(message) { label.text = message; opacity = 1; timer.restart() }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.px(56)
    width: label.implicitWidth + Theme.px(48); height: Theme.px(56)
    radius: height / 2
    color: "#EE2A3348"
    opacity: 0
    visible: opacity > 0
    z: 1000
    Behavior on opacity { NumberAnimation { duration: 200 } }
    Text {
        id: label
        anchors.centerIn: parent
        color: Theme.text
        font.family: Theme.font; font.pixelSize: Theme.px(18)
    }
    Timer { id: timer; interval: 3500; onTriggered: toast.opacity = 0 }
}
