import QtQuick

// Full-screen 4-digit PIN entry for the remote (arrows + OK), number keys, or mouse.
FocusScope {
    id: pad
    property string title: "Enter PIN"
    property string subtitle
    property string error
    property string entered
    property bool busy: false
    property var onPin: null          // called with the 4 digits
    property Item returnFocus: null   // what had focus before; it gets it back on close
    signal submitted(string pin)
    signal cancelled()

    function open(t, s, handler) {
        title = t; subtitle = s || ""; error = ""; entered = ""; busy = false
        if (handler) onPin = handler
        if (!visible) returnFocus = Window.activeFocusItem
        visible = true
        keys.itemAt(4).forceActiveFocus()
    }
    function close() {
        visible = false
        if (returnFocus && returnFocus.visible) returnFocus.forceActiveFocus()
        else parent.forceActiveFocus()
        returnFocus = null
    }
    function fail(message) { error = message; entered = ""; busy = false; shake.start() }

    anchors.fill: parent
    visible: false
    z: 500

    function press(k) {
        if (busy) return
        if (k === "Clear") entered = ""
        else if (k === "Delete") entered = entered.slice(0, -1)
        else if (entered.length < 4) entered += k
        error = ""
        if (entered.length === 4) { busy = true; submitTimer.start() }
    }
    Timer { id: submitTimer; interval: 150; onTriggered: { pad.submitted(pad.entered); if (pad.onPin) pad.onPin(pad.entered) } }

    Rectangle { anchors.fill: parent; color: "#CC05070D"; MouseArea { anchors.fill: parent } }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Theme.px(400); height: col.height + Theme.px(64)
        radius: Theme.px(20)
        color: Theme.surface
        SequentialAnimation on anchors.horizontalCenterOffset {
            id: shake; running: false
            NumberAnimation { to: Theme.px(24); duration: 50 }
            NumberAnimation { to: -Theme.px(24); duration: 80 }
            NumberAnimation { to: Theme.px(12); duration: 60 }
            NumberAnimation { to: 0; duration: 60 }
        }
        Column {
            id: col
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.px(32)
            spacing: Theme.px(14)
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: pad.title; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(26); font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; visible: text !== ""; text: pad.subtitle; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(16) }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.px(20)
                topPadding: Theme.px(8)
                Repeater {
                    model: 4
                    Rectangle {
                        width: Theme.px(18); height: width; radius: width / 2
                        color: index < pad.entered.length ? "white" : "transparent"
                        border.width: Theme.px(2); border.color: "white"
                    }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; height: Theme.px(22); text: pad.error; color: Theme.error; font.family: Theme.font; font.pixelSize: Theme.px(15) }
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3; spacing: Theme.px(12)
                Repeater {
                    id: keys
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "Clear", "0", "Delete"]
                    FocusScope {
                        id: key
                        width: Theme.px(96); height: Theme.px(64)
                        activeFocusOnTab: true
                        scale: activeFocus ? 1.08 : 1
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Rectangle {
                            anchors.fill: parent; radius: Theme.px(12)
                            color: Theme.surfaceHi
                            border.width: key.activeFocus ? Theme.px(3) : 0; border.color: "white"
                            Text { anchors.centerIn: parent; text: modelData; color: Theme.text; font.family: Theme.font; font.bold: true; font.pixelSize: modelData.length === 1 ? Theme.px(26) : Theme.px(16) }
                        }
                        Keys.onReturnPressed: pad.press(modelData)
                        Keys.onEnterPressed: pad.press(modelData)
                        Keys.onLeftPressed: if (index % 3 > 0) keys.itemAt(index - 1).forceActiveFocus()
                        Keys.onRightPressed: if (index % 3 < 2) keys.itemAt(index + 1).forceActiveFocus()
                        Keys.onUpPressed: if (index >= 3) keys.itemAt(index - 3).forceActiveFocus()
                        Keys.onDownPressed: if (index < 9) keys.itemAt(index + 3).forceActiveFocus()
                        MouseArea { anchors.fill: parent; onClicked: { key.forceActiveFocus(); pad.press(modelData) } }
                    }
                }
            }
        }
    }

    Keys.onPressed: (event) => {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) { press(String(event.key - Qt.Key_0)); event.accepted = true }
        else if (event.key === Qt.Key_Backspace) { press("Delete"); event.accepted = true }
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) { close(); cancelled(); event.accepted = true }
    }
}
