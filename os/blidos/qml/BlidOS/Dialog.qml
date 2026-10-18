import QtQuick

// Modal prompt: open({ title, message, input, password, placeholder, text, buttons: [{ text, primary, action(value) }] }).
FocusScope {
    id: dialog
    property var spec: ({})
    property var buttons: []
    property Item returnFocus: null  // what had focus before; it gets it back on close
    anchors.fill: parent
    // Opens and closes with a fade and a slight zoom; "shown" is the state, visible lasts until the fade ends.
    property bool shown: false
    visible: shown || opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    z: 400

    function open(s) {
        if (!shown) returnFocus = Window.activeFocusItem
        spec = s
        buttons = s.buttons || [{ text: "OK", primary: true }]
        field.text = s.text || ""
        shown = true
        if (s.input) field.forceActiveFocus()
        else buttonRow.children[0].forceActiveFocus()
    }
    function close() {
        shown = false
        // A hidden dialog must not keep focus: OK would press its buttons again and Back would do nothing.
        if (returnFocus && returnFocus.visible) returnFocus.forceActiveFocus()
        else parent.forceActiveFocus()
        returnFocus = null
    }
    function choose(b) { close(); if (b.action) b.action(field.text) }

    Rectangle { anchors.fill: parent; color: "#CC05070D"; MouseArea { anchors.fill: parent } }
    Rectangle {
        anchors.centerIn: parent
        scale: dialog.shown ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        width: Math.min(parent.width - Theme.px(160), Theme.px(760))
        height: col.height + Theme.px(72)
        radius: Theme.px(20)
        color: Theme.surface
        Column {
            id: col
            x: Theme.px(40); y: Theme.px(36)
            width: parent.width - Theme.px(80)
            spacing: Theme.px(18)
            Text { width: parent.width; wrapMode: Text.WordWrap; text: dialog.spec.title || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(28); font.bold: true }
            Text { width: parent.width; visible: text !== ""; wrapMode: Text.WordWrap; text: dialog.spec.message || ""; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(18) }
            Field {
                id: field
                visible: !!dialog.spec.input
                width: parent.width
                placeholderText: dialog.spec.placeholder || ""
                echoMode: dialog.spec.password ? TextInput.Password : TextInput.Normal
                Keys.onReturnPressed: dialog.choose(dialog.buttons[0])
                Keys.onEnterPressed: dialog.choose(dialog.buttons[0])
                Keys.onDownPressed: buttonRow.children[0].forceActiveFocus()
            }
            Flow {
                id: buttonRow
                width: parent.width
                spacing: Theme.px(14)
                Repeater {
                    model: dialog.buttons
                    PillButton {
                        text: modelData.text
                        primary: !!modelData.primary
                        onActivated: dialog.choose(modelData)
                        KeyNavigation.right: index + 1 < buttonRow.children.length - 1 ? buttonRow.children[index + 1] : null
                        KeyNavigation.left: index > 0 ? buttonRow.children[index - 1] : null
                        KeyNavigation.up: field.visible ? field : null
                    }
                }
            }
        }
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) { close(); event.accepted = true }
    }
}
